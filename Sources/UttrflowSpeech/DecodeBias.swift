// The one rule for whether a decode of a piece carries the user's words, so no retry path decides it alone.

/// Whether a re-decode of a piece keeps the first decode's vocabulary bias or drops it with the prompt.
enum DecodeBias {
    /// A tail or temperature re-decode of the same audio, which stays on the first decode's distribution.
    case same
    /// A re-decode that exists because the biased decode produced no words, so it must not repeat the bias.
    case none

    /// The vocabulary a decode under this rule is handed.
    func vocabulary(of original: [String]) -> [String] {
        switch self {
        case .same: original
        case .none: []
        }
    }

    /// The words a decode biases towards: what the prompt packed when it carries the words, else the vocabulary itself.
    static func words(vocabulary: [String], packed: [String], promptWords: Bool) -> [String] {
        promptWords ? packed : vocabulary
    }
}
