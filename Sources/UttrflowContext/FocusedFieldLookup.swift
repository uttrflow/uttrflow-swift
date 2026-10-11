import UttrflowCore

/// The application's focused element, or why the window read has none to read.
enum FocusedFieldLookup<Field> {
    case found(Field)
    case missing(ContextUnavailableReason)

    /// The element an answer names, else the answer's refusal, else no focused element at all.
    init(_ answer: FieldAnswer, decode: (Any) -> Field?) {
        if let field = answer.object.flatMap(decode) {
            self = .found(field)
        } else {
            self = .missing(answer.unavailable ?? .noFocusedElement)
        }
    }
}
