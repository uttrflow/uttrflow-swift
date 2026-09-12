public import UttrflowCore

/// Puts text into the focused app by pasting it, which works almost everywhere. See `Docs/insertion.md`.
public actor PasteboardTextInsertionEngine: TextInsertionEngine {
    public nonisolated let method: TextInsertionMethod = .pasteboard

    private let focus: any AccessibilityFocus
    private let pasteboard: any Pasteboard
    private let keystrokes: any KeystrokeSender
    private let confirmation: PasteConfirmation
    private let report: (@Sendable (PasteConfirmation.Outcome) -> Void)?

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
        pasteboard.setText(text, richText: richText)
        // Thrown onwards with the words left on the clipboard: the floor below would only put them back.
        try keystrokes.sendPaste()
        // Posting a paste proves nothing, so this waits for the words the way the write above is read back.
        let outcome = await confirmation.waitFor(text)
        // Waited for before the reporter is consulted, so attaching a logger cannot be what switches this on.
        report?(outcome)
        // The borrowed clipboard is deliberately never restored. See `Docs/insertion.md`.
        return InsertionArrival(outcome)
    }
}

extension InsertionArrival {
    /// Reads the confirmation's answer as what the insertion route reports upwards, dropping only the timing.
    public init(_ outcome: PasteConfirmation.Outcome) {
        switch outcome {
        case .landed: self = .confirmed
        case .notReported: self = .notReported
        case .gaveUp: self = .unconfirmed
        }
    }
}
