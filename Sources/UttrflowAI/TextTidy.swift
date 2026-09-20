import UttrflowCore

/// String-level repairs for text that is not a draft: a language model's answer, a snippet, a window title.
public enum TextTidy {
    /// Collapses runs of whitespace and trims the ends.
    public static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Lower-cased runs of letters and digits, read off the one splitter every word comparison uses.
    static func words(_ text: String) -> [String] { WordShape.words(text) }

    /// Tidies spacing but keeps the line breaks a model's answer may mean. See Docs/ai-model-output.md.
    public static func collapseSpacing(_ text: String) -> String {
        var result = ""
        var lineStart = text.startIndex
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "\n" || text[index] == "\r" else {
                index = text.index(after: index)
                continue
            }
            result += tidyLine(text[lineStart..<index])
            let delimiterStart = index
            index = text.index(after: index)
            if text[delimiterStart] == "\r", index < text.endIndex, text[index] == "\n" {
                index = text.index(after: index)
            }
            result += "\n"
            lineStart = index
        }
        result += tidyLine(text[lineStart...])
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Collapses horizontal whitespace without consuming the line's delimiter.
    private static func tidyLine(_ line: Substring) -> String {
        var result = ""
        var pendingSpace = false
        for character in line {
            if character == " " || character == "\t" {
                pendingSpace = true
            } else {
                if pendingSpace, !result.isEmpty { result.append(" ") }
                result.append(character)
                pendingSpace = false
            }
        }
        return result
    }
}
