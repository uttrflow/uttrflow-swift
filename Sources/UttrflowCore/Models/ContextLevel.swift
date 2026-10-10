/// How much of the front application a dictation may read; in Core because settings and the reader both need it.
public enum ContextLevel: String, Sendable, Equatable, CaseIterable, Codable {
    /// The application's name and bundle identifier only: no window title, selection or field text.
    case identity
    /// The window title, the selection and the text around the caret as well. The default.
    case nearCaret
}
