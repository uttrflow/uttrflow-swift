public import UttrflowCore

/// The text field the user is typing in, reduced to the one operation insertion needs.
///
/// Replacing *the selection* is the whole contract. With a caret and no selection that
/// inserts at the caret; with text selected it replaces exactly what was selected —
/// which is what the user asked for by selecting it. Nothing here can touch the rest
/// of the field, so "never overwrite content the user did not select" is guaranteed by
/// the shape of the API rather than by remembering to be careful.
public protocol FocusedTextField: Sendable {
    func replaceSelection(with text: String) throws(TextInsertionError)
}

/// Finds the text field the user is typing in.
public protocol AccessibilityFocus: Sendable {
    /// The focused text field, or `nil` when what is focused cannot take text.
    func focusedTextField() -> (any FocusedTextField)?

    /// Whether anything at all is focused that could plausibly receive typing.
    ///
    /// Deliberately weaker than ``focusedTextField()``, and the gap between them is the
    /// point. That one additionally requires the element to report its *selection*, and
    /// plenty of fields refuse the read while happily accepting a paste — Electron apps,
    /// web views, and anything drawing its own text. Pasting needs to know only that
    /// there is somewhere for a ⌘V to land, and answering the stricter question on its
    /// behalf sends every one of those apps to the clipboard instead of their document.
    func hasFocusedElement() -> Bool

    /// Whether Uttrflow itself is the application in front.
    ///
    /// Nothing may be typed or pasted in that case: the target would be Uttrflow's own
    /// window, and the user's dictation would land in the app that produced it.
    func isSelfFrontmost() -> Bool
}
