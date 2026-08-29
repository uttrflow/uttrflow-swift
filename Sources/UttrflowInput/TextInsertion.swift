import UttrflowCore

/// Builds the insertion strategies, in the order they should be tried.
///
/// The one place that names concrete strategies. Everything above sees a coordinator.
public enum TextInsertion {
    /// Accessibility first because it leaves the clipboard alone and puts the text
    /// exactly at the caret. Pasting next because it works almost everywhere.
    /// The clipboard last because it cannot fail, which is what stops a user ever
    /// losing words to an app that refuses both.
    ///
    /// Pasting shares the focus reader with the first strategy, and needs it: without a
    /// way to tell that nothing is focused, it claimed success into thin air and then
    /// restored the clipboard over the dictation, so the floor below was never reached
    /// and the words were gone from everywhere.
    public static func coordinator(
        focus: any AccessibilityFocus = AXAccessibilityFocus(),
        pasteboard: any Pasteboard = SystemPasteboard(),
        keystrokes: any KeystrokeSender = CGEventKeystrokeSender()
    ) -> TextInsertionCoordinator {
        TextInsertionCoordinator(strategies: [
            AccessibilityTextInsertionEngine(focus: focus),
            PasteboardTextInsertionEngine(
                focus: focus, pasteboard: pasteboard, keystrokes: keystrokes),
            ClipboardTextInsertionEngine(pasteboard: pasteboard),
        ])
    }
}
