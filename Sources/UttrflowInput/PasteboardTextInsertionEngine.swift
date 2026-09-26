public import UttrflowCore

/// Puts text into the focused app by pasting it, which works almost everywhere. See `Docs/insertion.md`.
public actor PasteboardTextInsertionEngine: TextInsertionEngine {
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
        // The clipboard is the user's, so a stage that has given up must not take it. See `Docs/insertion.md`.
        guard !Task.isCancelled else {
            throw .insertionRejected(description: TextInsertion.dictationEnded)
        }
        landedIn = nil
        // Re-checked here rather than trusted from `canInsert()`, whose answer can go stale by now.
        guard !focus.isSelfFrontmost() else {
            throw .noFocusedTextField
        }
        // Concealed for a field that hides what is typed, so no clipboard history keeps the words.
        if focus.focusedFieldIsSecure() {
            pasteboard.setConcealedText(text)
        } else {
            pasteboard.setText(text, richText: richText)
        }
        // Read before the paste is posted, so an unchanged caret cannot be read back as a fresh landing.
        let before = focus.tail(upTo: PasteConfirmation.readLength)
        // Thrown onwards with the words left on the clipboard: the floor below would only put them back.
        try keystrokes.sendPaste()
        // Read as the paste is posted, not after the wait below, so a switch during the wait is not credited.
        landedIn = focus.frontmostApplication()
        // Posting a paste proves nothing, so this waits for the words the way the write above is read back.
        let outcome = await confirmation.waitFor(text, before: before)
        // Waited for before the reporter is consulted, so attaching a logger cannot be what switches this on.
        report?(outcome)
        // The borrowed clipboard is deliberately never restored. See `Docs/insertion.md`.
        return InsertionArrival(outcome)
    }

    /// The application in front as the last paste was posted.
    public func destinationAtLanding() async -> InsertionDestination? { landedIn }
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
