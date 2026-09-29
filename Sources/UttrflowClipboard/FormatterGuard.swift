/// Decides whether a formatter's output may be shown at all: the tokens must round-trip.
public enum FormatterGuard {
    /// Whether `formatted` may be offered in place of `original`; anything unaccounted for is a difference.
    public static func isFaithful(_ formatted: String, to original: String) -> Bool {
        significant(formatted) == significant(original)
    }

    /// Punctuation a formatter may add, drop or swap without changing what the code means.
    static let layout: Set<Character> = [",", ";"]

    /// The significant code, literal and comment tokens in order, ignoring only code whitespace and layout.
    static func significant(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" || character == "'" || character == "`" {
                flush(&current, into: &tokens)
                let delimiter = character
                var literal = String(character)
                index += 1
                while index < characters.count {
                    let next = characters[index]
                    literal.append(next)
                    index += 1
                    if next == "\\", index < characters.count {
                        literal.append(characters[index])
                        index += 1
                    } else if next == delimiter {
                        break
                    }
                }
                tokens.append("literal:\(literal)")
                continue
            }
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
                index += 1
                continue
            }
            if character == "/", index + 1 < characters.count, characters[index + 1] == "/" {
                flush(&current, into: &tokens)
                var comment = "//"
                index += 2
                while index < characters.count, characters[index] != "\n", characters[index] != "\r" {
                    comment.append(characters[index])
                    index += 1
                }
                tokens.append("comment:\(comment)")
                continue
            }
            flush(&current, into: &tokens)
            if !character.isWhitespace, !layout.contains(character) {
                tokens.append(String(character))
            }
            index += 1
        }
        flush(&current, into: &tokens)
        return tokens
    }

    /// Emits a pending code word before a non-word token.
    private static func flush(_ current: inout String, into tokens: inout [String]) {
        guard !current.isEmpty else { return }
        tokens.append(current)
        current = ""
    }
}
