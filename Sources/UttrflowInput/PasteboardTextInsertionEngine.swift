public import UttrflowCore

/// Puts text into the focused app by pasting it, which works almost everywhere. See `Docs/insertion.md`.
public actor PasteboardTextInsertionEngine: TextInsertionEngine {
    private static let insertionGate = PasteboardInsertionGate()

    public nonisolated let method: TextInsertionMethod = .pasteboard

    private let focus: any AccessibilityFocus
    private let pasteboard: any Pasteboard
    private let keystrokes: any KeystrokeSender
    private let confirmation: PasteConfirmation
    private let report: (@Sendable (PasteConfirmation.Outcome) -> Void)?
    /// What was in front when the last paste was posted, which is where its words went.
    private var landedIn: InsertionDestination?

    public init(
        focus: any AccessibilityFocus,
        pasteboard: any Pasteboard,
        keystrokes: any KeystrokeSender,
        confirmation: PasteConfirmation? = nil,
        reporting: (@Sendable (PasteConfirmation.Outcome) -> Void)? = nil
    ) {
        self.focus = focus
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.confirmation = confirmation ?? PasteConfirmation(focus: focus)
        self.report = reporting
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
        await gate.acquire()
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
        guard !Task.isCancelled else {
            throw .insertionRejected(description: TextInsertion.dictationEnded)
        }
        landedIn = nil
        // Re-checked here rather than trusted from `canInsert()`, whose answer can go stale by now.
        try PasteboardPasteAction.requireExternal(focus: focus)
        try refuseIfTargetChanged(destination)
        // Concealed for a field that hides what is typed, so no clipboard history keeps the words.
        let focus = focus
        if await AccessibilityThread.run(orElse: true, { focus.focusedFieldIsSecure() }) {
            pasteboard.setConcealedText(text)
        } else {
            pasteboard.setText(text, richText: richText)
        }
        // A write that did not stick would paste whatever the clipboard held before, so the next route takes over.
        guard pasteboard.text() == text else { throw .clipboardUnavailable }
        // Read before the paste is posted, so an unchanged caret cannot be read back as a fresh landing.
        let before = await AccessibilityThread.run(orElse: .unreadable) {
            focus.tail(upTo: PasteConfirmation.readLength)
        }
        try refuseIfTargetChanged(destination)
        // Thrown onwards with the words left on the clipboard: the floor below would only put them back.
        try PasteboardPasteAction.postIfExternal(focus: focus, keystrokes: keystrokes)
        // Read as the paste is posted, not after the wait below, so a switch during the wait is not credited.
        landedIn = focus.frontmostApplication()
        // Posting a paste proves nothing, so this waits for the words the way the write above is read back.
        let outcome = await confirmation.waitFor(text, before: before)
        // Waited for before the reporter is consulted, so attaching a logger cannot be what switches this on.
        report?(outcome)
        // The borrowed clipboard is deliberately never restored. See `Docs/insertion.md`.
        return InsertionArrival(outcome)
    }

    private func refuseIfTargetChanged(_ destination: InsertionDestination?) throws(TextInsertionError) {
        guard let destination else { return }
        guard destination.isKnown, let expected = destination.bundleIdentifier,
            focus.frontmostApplication()?.bundleIdentifier == expected
        else { throw .insertionTargetChanged }
    }

    /// The application in front as the last paste was posted.
    public func destinationAtLanding() async -> InsertionDestination? { landedIn }
}

/// Re-checks the frontmost application immediately before posting a paste keystroke.
enum PasteboardPasteAction {
    /// Posts ⌘V only while an application other than Uttrflow is frontmost.
    static func postIfExternal(
        focus: any AccessibilityFocus, keystrokes: any KeystrokeSender
    ) throws(TextInsertionError) {
        try requireExternal(focus: focus)
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

    func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
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
