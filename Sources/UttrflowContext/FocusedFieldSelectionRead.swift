/// The outcome of a bounded read of the focused field's selection.
public enum FocusedFieldSelectionRead: Sendable, Equatable {
    /// Accessibility returned the selected range and the field that owns it.
    case selection(FocusedFieldSelection)
    /// Accessibility answered, but did not identify a usable focused selection.
    case unavailable
    /// The selection read did not answer within its time allowance.
    case timedOut
}
