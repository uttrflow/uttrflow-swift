/// What a flagged dictation got wrong, in the error classes of `Docs/accuracy-targets.md`.
public enum FlagReason: String, Sendable, Equatable, Codable, CaseIterable {
    /// A wrong, dropped or invented word, a rewrite, or a mark that changes what is asserted.
    case meaningChanging
    /// A stop, comma, capital, number form, break or left-in filler at the same meaning.
    case formatting
    /// Spacing only.
    case cosmetic
}
