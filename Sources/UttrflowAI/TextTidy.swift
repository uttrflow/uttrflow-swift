/// Deterministic, pure text repairs shared by the rule-based transformer and the model-backed ones.
public enum TextTidy {
    /// Whole-word fillers never meaningful on their own; "like" and "well" are ordinary words too often.
    static let fillerWords: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "er", "erm", "ah", "hmm", "mmm"]

    /// Collapses runs of whitespace and trims the ends.
    public static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Lower-cased runs of letters and digits, which is the unit every comparison here counts in.
    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Tidies spacing but keeps the line breaks a model's answer may mean. See Docs/ai-model-output.md.
    public static func collapseSpacing(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes filler words, and the doubled word a false start leaves behind.
    public static func removeFillers(_ text: String) -> String {
        var kept: [Substring] = []
        for word in text.split(whereSeparator: \.isWhitespace) {
            let bare = word.lowercased().filter { $0.isLetter }
            if fillerWords.contains(bare), word.allSatisfy({ $0.isLetter || $0.isPunctuation }) {
                continue
            }
            // "the the deployment" — a stammer, not emphasis.
            if let previous = kept.last, previous.lowercased() == word.lowercased(), word.count <= 4 {
                continue
            }
            kept.append(word)
        }
        return kept.joined(separator: " ")
    }

    /// Capitalises the first letter of the text and of each new sentence.
    public static func capitaliseSentences(_ text: String) -> String {
        var result = ""
        var startOfSentence = true
        for character in text {
            // Any visible character ends the start of a sentence, or "42 things" capitalises the wrong word.
            if startOfSentence, !character.isWhitespace {
                result.append(contentsOf: character.uppercased())
                startOfSentence = false
            } else {
                result.append(character)
                if character == "." || character == "!" || character == "?" {
                    startOfSentence = true
                }
            }
        }
        return result
    }

    /// Capitalises the pronoun "i" where it stands alone.
    public static func capitalisePronounI(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> String in
                guard word.filter(\.isLetter) == "i" else { return String(word) }
                return String(word.map { $0 == "i" ? "I" : $0 })
            }
            .joined(separator: " ")
    }

    /// Adds a full stop to a plain unfinished sentence, never to text with a line break or code-like ending.
    public static func ensureTerminalPunctuation(_ text: String) -> String {
        guard let last = text.last, !text.contains(where: \.isNewline) else { return text }
        let alreadyFinished: Set<Character> = [".", "!", "?", ";", ":", ")", "}", "]", ",", "\"", "'", "…"]
        guard !alreadyFinished.contains(last), last.isLetter || last.isNumber else { return text }
        return text + "."
    }
}
