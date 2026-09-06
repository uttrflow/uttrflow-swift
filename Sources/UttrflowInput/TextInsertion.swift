import UttrflowCore

/// Builds the insertion strategies in the order they are tried, and is the one place that names them.
public enum TextInsertion {
    /// Accessibility, then pasting, then the clipboard, which cannot fail. See `Docs/insertion.md`.
    public static func coordinator(
        focus: any AccessibilityFocus = AXAccessibilityFocus(),
        pasteboard: any Pasteboard = SystemPasteboard(),
        keystrokes: any KeystrokeSender = CGEventKeystrokeSender(),
        reporting: (@Sendable (PasteConfirmation.Outcome) -> Void)? = nil
    ) -> TextInsertionCoordinator {
        TextInsertionCoordinator(strategies: [
            AccessibilityTextInsertionEngine(focus: focus),
            PasteboardTextInsertionEngine(
                focus: focus, pasteboard: pasteboard, keystrokes: keystrokes, reporting: reporting),
            ClipboardTextInsertionEngine(pasteboard: pasteboard),
        ])
    }

    /// The route an accepted suggestion takes, which has no clipboard in it at all. See `Docs/predict-accept.md`.
    public static func completion(
        focus: any AccessibilityFocus = AXAccessibilityFocus(),
        typist: any KeystrokeTyping = CGEventTypist()
    ) -> CompletionRoute {
        CompletionRoute(strategies: [
            AccessibilityTextInsertionEngine(focus: focus),
            TypedTextInsertionEngine(focus: focus, typist: typist),
        ])
    }
}
