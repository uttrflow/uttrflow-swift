public import UttrflowCore

/// The text field the user is typing in, reduced to the two writes insertion needs. See `Docs/predict-accept.md`.
public protocol FocusedTextField: Sendable {
    /// Replaces the selection, or inserts at the caret when there is none.
    func replaceSelection(with text: String) throws(TextInsertionError)

    /// Replaces the selection *and* the `characters` before it, which only an accepted completion asks for.
    func replaceSelection(
        precededBy characters: Int, with text: String
    ) throws(TextInsertionError)
}

extension FocusedTextField {
    /// A field that cannot select backwards refuses, so the keystroke route takes the replacement instead.
    public func replaceSelection(
        precededBy characters: Int, with text: String
    ) throws(TextInsertionError) {
        guard characters == 0 else {
            throw .insertionRejected(description: "the field cannot select backwards")
        }
        try replaceSelection(with: text)
    }
}

/// Finds the text field the user is typing in.
public protocol AccessibilityFocus: Sendable {
    /// The focused text field, or `nil` when what is focused cannot take text.
    func focusedTextField() -> (any FocusedTextField)?

    /// Whether anything at all is focused that could take a paste, which many fields allow while refusing a selection read.
    func hasFocusedElement() -> Bool

    /// Whether Uttrflow itself is the application in front, in which case nothing may be typed or pasted.
    func isSelfFrontmost() -> Bool
}
