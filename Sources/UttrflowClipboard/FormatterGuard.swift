/// Decides whether a formatter's output may be shown at all: the tokens must round-trip.
public enum FormatterGuard {
    /// Whether `formatted` may be offered in place of `original`; anything unaccounted for is a difference.
    public static func isFaithful(_ formatted: String, to original: String) -> Bool {
        significant(formatted) == significant(original)
    }

    /// Punctuation a formatter may add, drop or swap without changing what the code means.
    static let layout: Set<Character> = [",", ";", "\"", "'", "`"]

    /// The words, numbers and operator characters of some code, in order; whitespace, layout and `//` markers are dropped.
    static func significant(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
                index += 1
                continue
            }
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
            if character == "/", index + 1 < characters.count, characters[index + 1] == "/" {
                index += 2
                continue
            }
            if !character.isWhitespace, !layout.contains(character) {
                tokens.append(String(character))
            }
            index += 1
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
