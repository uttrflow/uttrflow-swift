// The one rule for whether a decode of a piece carries the user's words, so no retry path decides it alone.

/// Whether a re-decode of a piece keeps the first decode's prompt and vocabulary bias or drops both.
public enum DecodeBias: Sendable, Equatable {
    /// A tail or temperature re-decode of the same audio, which stays on the first decode's distribution.
    case same
    /// A re-decode that exists because the biased decode produced no words, so it must not repeat the bias.
    case none

    /// The options a decode under this rule is given, derived from the first decode's.
    public func options(_ first: TranscriptionOptions) -> TranscriptionOptions {
        switch self {
        case .same: first
        case .none: TranscriptionOptions(languageHint: first.languageHint)
        }
    }

    /// The words a decode biases towards: what the prompt packed when it carries the words, else the vocabulary itself.
    public static func words(vocabulary: [String], packed: [String], promptWords: Bool) -> [String] {
        promptWords ? packed : vocabulary
    }
}
