/// String-level repairs for text that is not a draft: a language model's answer, a snippet, a window title.
public enum TextTidy {
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

    /// Adds a full stop to a plain sentence with no ending; code and text with a line break are untouched.
    public static func ensureTerminalPunctuation(_ text: String) -> String {
        guard let last = text.last, !text.contains(where: \.isNewline) else { return text }
        let alreadyFinished: Set<Character> = [".", "!", "?", ";", ":", ")", "}", "]", ",", "\"", "'", "…"]
        guard !alreadyFinished.contains(last), last.isLetter || last.isNumber else { return text }
        return text + "."
    }
}
