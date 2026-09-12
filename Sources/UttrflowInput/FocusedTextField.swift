public import UttrflowCore

/// The text field the user is typing in, reduced to the two writes insertion needs. See `Docs/predict-accept.md`.
public protocol FocusedTextField: Sendable {
    /// Replaces the selection, or inserts at the caret when there is none.
    func replaceSelection(with text: String) throws(TextInsertionError)

    /// Replaces the selection *and* `replaced` before it, having confirmed that is what is there; only a completion asks.
    func replaceSelection(
        replacing replaced: String, with text: String
    ) throws(TextInsertionError)
}

extension FocusedTextField {
    /// A field that cannot select backwards refuses, so the keystroke route takes the replacement instead.
    public func replaceSelection(
        replacing replaced: String, with text: String
    ) throws(TextInsertionError) {
        guard replaced.isEmpty else {
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

    /// The `count` characters immediately before the caret, or `nil` when the field will not say.
    func precedingText(_ count: Int) -> String?

    /// As much of the text before the caret as there is, up to `count`, or that the field will not say.
    func tail(upTo count: Int) -> FieldTail

    /// The application in front right now, which is where a write lands. See `Docs/insertion.md`.
    func frontmostApplication() -> InsertionDestination?
}

/// What a field says about the text before its caret, keeping "too short" apart from "will not say".
public enum FieldTail: Sendable, Equatable {
    /// Everything before the caret, up to what was asked for; shorter than that means the field is shorter.
    case text(String)
    /// The field reports neither its value nor its caret.
    case unreadable
}

extension AccessibilityFocus {
    /// Most fields on the typed route cannot be read, so the guard falls back to the cap alone.
    public func precedingText(_ count: Int) -> String? { nil }

    /// The same default: a field that will not report its value will not report its tail either.
    public func tail(upTo count: Int) -> FieldTail { .unreadable }

    /// A reader with no window server behind it cannot say what is in front, and says so.
    public func frontmostApplication() -> InsertionDestination? { nil }
}
