/// How a recorded line reached the corpus, which decides whether a longer line may later retire it.
public enum LineOrigin: Sendable, Equatable {
    /// Typed by the person with no ending that finishes it, such as a draft an idle left standing.
    case typed
    /// A suggestion the person accepted.
    case suggestion
    /// Typed by the person and finished with Return or by leaving the field, so it is a line of its own.
    case finished

    /// Whether the line came from a suggestion rather than the person's own typing.
    var isSelfSourced: Bool {
        switch self {
        case .suggestion: true
        case .typed, .finished: false
        }
    }
}
