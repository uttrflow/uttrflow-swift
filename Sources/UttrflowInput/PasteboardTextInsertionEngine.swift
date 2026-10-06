public import UttrflowCore

/// Puts text into the focused app by pasting it, which works almost everywhere. See `Docs/insertion.md`.
public actor PasteboardTextInsertionEngine: TextInsertionEngine {
    private static let insertionGate = PasteboardInsertionGate()

    public nonisolated let method: TextInsertionMethod = .pasteboard

    private let focus: any AccessibilityFocus
    private let pasteboard: any Pasteboard
    private let keystrokes: any KeystrokeSender
    private let confirmation: PasteConfirmation
    private let confirmsArrival: Bool
    /// Whether a refused paste key leaves the words on the clipboard, as a route with a clipboard floor wants.
    private let keepsWordsWhenRefused: Bool
    private let report: (@Sendable (PasteConfirmation.Outcome) -> Void)?
    private let onWaitingForGate: @Sendable () -> Void
    /// What was in front when the last paste was posted, which is where its words went.
    private var landedIn: InsertionDestination?

    public init(
        focus: any AccessibilityFocus,
        pasteboard: any Pasteboard,
        keystrokes: any KeystrokeSender,
        confirmation: PasteConfirmation? = nil,
        confirmsArrival: Bool = true,
        keepsWordsWhenRefused: Bool = true,
        reporting: (@Sendable (PasteConfirmation.Outcome) -> Void)? = nil
    ) {
        self.init(
            focus: focus, pasteboard: pasteboard, keystrokes: keystrokes, confirmation: confirmation,
            confirmsArrival: confirmsArrival, keepsWordsWhenRefused: keepsWordsWhenRefused,
            reporting: reporting, onWaitingForGate: {})
    }

    init(
        focus: any AccessibilityFocus,
        pasteboard: any Pasteboard,
        keystrokes: any KeystrokeSender,
        confirmation: PasteConfirmation? = nil,
        confirmsArrival: Bool = true,
        keepsWordsWhenRefused: Bool = true,
        reporting: (@Sendable (PasteConfirmation.Outcome) -> Void)? = nil,
        onWaitingForGate: @escaping @Sendable () -> Void
    ) {
        self.focus = focus
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.confirmation = confirmation ?? PasteConfirmation(focus: focus)
        self.confirmsArrival = confirmsArrival
        self.keepsWordsWhenRefused = keepsWordsWhenRefused
        self.report = reporting
        self.onWaitingForGate = onWaitingForGate
    }

    /// Anything but Uttrflow itself. See `Docs/input-paste-eligibility.md`.
    public func canInsert() async -> Bool { !focus.isSelfFrontmost() }

    public func insert(_ text: String) async throws(TextInsertionError) -> InsertionArrival {
        try await insert(text, richText: nil)
    }

    /// Puts both flavours up so the receiving application takes the one it understands.
    public func insert(
        _ text: String, richText: String?
    ) async throws(TextInsertionError) -> InsertionArrival {
        try await insertSerialized(text, richText: richText, targeting: nil)
    }

    public func insert(
        _ text: String, targeting destination: InsertionDestination
    ) async throws(TextInsertionError) -> InsertionArrival {
        try await insert(text, richText: nil, targeting: destination)
    }

    public func insert(
        _ text: String, richText: String?, targeting destination: InsertionDestination
    ) async throws(TextInsertionError) -> InsertionArrival {
        try await insertSerialized(text, richText: richText, targeting: destination)
    }

    private func insertSerialized(
        _ text: String, richText: String?, targeting destination: InsertionDestination?
    ) async throws(TextInsertionError) -> InsertionArrival {
        let gate = Self.insertionGate
        await gate.acquire(onWaiting: onWaitingForGate)
        do {
            let result = try await insertWhileSerialized(text, richText: richText, targeting: destination)
            await gate.release()
            return result
        } catch {
            await gate.release()
            throw error
        }
    }

    private func insertWhileSerialized(
        _ text: String, richText: String?, targeting destination: InsertionDestination?
    ) async throws(TextInsertionError) -> InsertionArrival {
        // The clipboard is the user's, so a stage that has given up must not take it. See `Docs/insertion.md`.
        try PasteboardInsertionCancellation.requireLive(on: pasteboard)
        landedIn = nil
        // Re-checked here rather than trusted from `canInsert()`, whose answer can go stale by now.
        try PasteboardPasteAction.requireExternal(focus: focus)
        try TextInsertion.requireTarget(destination, focus: focus)
        // Concealed for a field that hides what is typed, so no clipboard history keeps the words.
        let focus = focus
        let isSecure = await AccessibilityThread.run(orElse: true) { focus.focusedFieldIsSecure() }
        try TextInsertion.requireTarget(destination, focus: focus)
        try PasteboardInsertionCancellation.requireLive(on: pasteboard)
        // With no clipboard floor below, a paste key that cannot be posted must not cost the user's copy.
        guard keepsWordsWhenRefused || keystrokes.maySendPaste() else { throw .accessibilityDenied }
        let write: PasteboardWriteResult
        if isSecure {
            write = pasteboard.writeConcealedText(text)
        } else {
            write = pasteboard.writeTransientText(text, richText: richText)
        }
        try PasteboardInsertionCancellation.requireLive(
            on: pasteboard, afterWritingAt: write.changeCount)
        guard write.didWrite else { throw .clipboardUnavailable }
        let writeChangeCount = write.changeCount
        // A different clipboard generation means another writer owns it now.
        let readback = pasteboard.text()
        let readbackChangeCount = pasteboard.changeCount()
        if let writeChangeCount, let readbackChangeCount,
            writeChangeCount != readbackChangeCount
        {
            throw .clipboardChanged
        }
        guard readback == text else { throw .clipboardUnavailable }
        let verifiedChangeCount = writeChangeCount
        // Read before the paste is posted, so an unchanged caret cannot be read back as a fresh landing.
        let before: FieldTail =
            confirmsArrival
            ? await AccessibilityThread.run(orElse: .unreadable) {
                focus.tail(upTo: PasteConfirmation.readLength)
            }
            : .unreadable
        // AX may take long enough for another device or app to replace the clipboard.
        if let verifiedChangeCount, let currentChangeCount = pasteboard.changeCount(),
            currentChangeCount != verifiedChangeCount
        {
            throw .clipboardChanged
        }
        // Thrown onwards with the words left on the clipboard: the floor below would only put them back.
        try PasteboardPasteAction.postIfExternal(
            focus: focus, keystrokes: keystrokes, targeting: destination,
            pasteboard: pasteboard, writeChangeCount: verifiedChangeCount)
        // Read as the paste is posted, not after the wait below, so a switch during the wait is not credited.
        landedIn = focus.focusedApplication()
        // Posting a paste proves nothing, so this waits for the words the way the write above is read back.
        let outcome =
            confirmsArrival
            ? await confirmation.waitFor(text, before: before)
            : PasteConfirmation.Outcome.notReported
        // Panel insertion has no arrival notice, so it does not need to report confirmation either.
        if confirmsArrival { report?(outcome) }
        // The borrowed clipboard is deliberately never restored. See `Docs/insertion.md`.
        return InsertionArrival(outcome)
    }

    /// The application in front as the last paste was posted.
    public func destinationAtLanding() async -> InsertionDestination? { landedIn }
}

/// Re-checks the frontmost application immediately before posting a paste keystroke.
enum PasteboardPasteAction {
    /// Posts ⌘V only while an application other than Uttrflow is frontmost.
    static func postIfExternal(
        focus: any AccessibilityFocus, keystrokes: any KeystrokeSender,
        targeting destination: InsertionDestination? = nil,
        pasteboard: any Pasteboard, writeChangeCount: Int?
    ) throws(TextInsertionError) {
        try requireExternal(focus: focus)
        try TextInsertion.requireTarget(destination, focus: focus)
        try PasteboardInsertionCancellation.requireLive(
            on: pasteboard, afterWritingAt: writeChangeCount)
        try keystrokes.sendPaste()
    }

    /// Rejects a paste while Uttrflow is frontmost, before clipboard contents can be changed.
    static func requireExternal(focus: any AccessibilityFocus) throws(TextInsertionError) {
        guard !focus.isSelfFrontmost() else { throw .noFocusedTextField }
    }
}

private actor PasteboardInsertionGate {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire(onWaiting: @Sendable () -> Void) async {
        guard isHeld else {
            isHeld = true
            return
        }
        await withCheckedContinuation {
            waiters.append($0)
            onWaiting()
        }
    }

    func release() {
        guard !waiters.isEmpty else {
            isHeld = false
            return
        }
        waiters.removeFirst().resume()
    }
}

extension InsertionArrival {
    /// Reads the confirmation's answer as what the insertion route reports upwards, dropping only the timing.
    public init(_ outcome: PasteConfirmation.Outcome) {
        switch outcome {
        case .landed: self = .confirmed
        case .notReported: self = .notReported
        case .gaveUp, .cancelled: self = .unconfirmed
        }
    }
}
