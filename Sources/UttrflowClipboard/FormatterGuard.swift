/// Decides whether a formatter's output may be shown at all: the tokens must round-trip.
public enum FormatterGuard {
    /// Whether `formatted` may be offered in place of `original`; anything unaccounted for is a difference.
    public static func isFaithful(_ formatted: String, to original: String) -> Bool {
        significant(formatted) == significant(original)
    }

    /// The words, numbers and string contents of some code, in order; punctuation and whitespace are dropped.
    static func significant(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        for character in text {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
