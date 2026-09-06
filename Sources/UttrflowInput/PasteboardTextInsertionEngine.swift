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

    public func insert(_ text: String) async throws(TextInsertionError) {
        try await insert(text, richText: nil)
    }

    /// Puts both flavours up so the receiving application takes the one it understands.
    public func insert(_ text: String, richText: String?) async throws(TextInsertionError) {
        pasteboard.setText(text, richText: richText)
        // Thrown onwards with the words left on the clipboard: the floor below would only put them back.
        try keystrokes.sendPaste()
        // Posting a paste proves nothing, so this waits for the words the way the write above is read back.
        report?(await confirmation.waitFor(text))
        // The borrowed clipboard is deliberately never restored. See `Docs/insertion.md`.
    }
}
