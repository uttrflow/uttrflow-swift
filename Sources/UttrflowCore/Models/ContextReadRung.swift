/// Which step of the read ladder gives the text around the caret, carrying no text itself.
public enum ContextReadRung: String, Sendable, CaseIterable {
    /// A ranged read around the caret, taken when the value is longer than the window.
    case rangedValue
    /// The whole value, taken when it fits the window.
    case wholeValue
    /// The rendered row an editor draws around the empty input it parks at the caret.
    case renderedRows
    /// No rung answers: the field refuses, is secure, or gives a value that does not fit its count.
    case none
}
