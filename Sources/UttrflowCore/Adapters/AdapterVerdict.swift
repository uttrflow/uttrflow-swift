/// Whether an answer is well formed for the notation it is written in. See `Docs/adapters.md` §5.
public enum AdapterVerdict: Sendable, Equatable {
    /// The answer holds together as that notation, judged in the context of the caret's text.
    case wellFormed
    /// No notation is being written here, so there is nothing to judge.
    case notApplicable
    /// The answer breaks the notation's structure, and why; the router falls back to the rules.
    case malformed(reason: String)
}
