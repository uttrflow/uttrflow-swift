// The one step that writes each word in the spelling the user prefers.

/// Rewrites whole words to the spelling the user chose for them, keeping a capital first letter. See `Docs/learned-state.md`.
public enum PreferredSpelling {
    /// `text` with every whole word that is a key of `preferred`, compared lowercased, written as its value.
    public static func applied(to text: String, preferring preferred: [String: String]) -> String {
        guard !preferred.isEmpty else { return text }
        var output = ""
        var word = ""
        func flush() {
            output += respelled(word, preferring: preferred)
            word = ""
        }
        for character in text {
            if character.isLetter {
                word.append(character)
            } else {
                flush()
                output.append(character)
            }
        }
        flush()
        return output
    }

    private static func respelled(_ word: String, preferring preferred: [String: String]) -> String {
        guard !word.isEmpty, let chosen = preferred[word.lowercased()], let first = word.first else {
            return word
        }
        return first.isUppercase ? chosen.prefix(1).uppercased() + chosen.dropFirst() : chosen
    }
}
