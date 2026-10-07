// Unwraps a model's reply, with the whitespace trim it relies on.
/// Strips a bare label or whole-answer quotes from a model's reply. See Docs/ai-model-output.md.
public enum ResponseUnwrapper {
    /// Labels a model echoes from the worked examples; a sentence is not a label and is left for the guard.
    private static let labels = [
        "cleaned", "output", "result", "text", "response", "answer", "corrected", "rewritten",
    ]

    /// The answer without its wrapper; a label the speaker opened any line with ("Output: ship it") stays.
    public static func unwrap(_ rewritten: String, spoken: String) -> String {
        let said = openingWords(of: spoken)
        // The prompt folded the speaker's double quotes to single, so they go back before quotes are judged.
        let restored = PromptText.restoringDoubleQuotes(in: rewritten, from: spoken)
        var text = lastLabelledLine(in: restored.trimmed(), unless: said)
        text = stripLabel(from: text, unless: said)
        text = stripSurroundingQuotes(text, unless: spoken)
        text = stripMarkup(from: text, unless: spoken)
        // A model that wrote `Cleaned: "…"` needs both removed, in that order.
        return stripLabel(from: text, unless: said).trimmed()
    }

    /// The first word of every line of the draft, lowercased and without punctuation: where a speaker's own label stands.
    private static func openingWords(of spoken: String) -> Set<String> {
        Set(
            spoken.split(whereSeparator: \.isNewline).compactMap { line in
                line.split(whereSeparator: \.isWhitespace).first.map {
                    String($0.filter(\.isLetter)).lowercased()
                }
            })
    }

    /// The answer from a reply that replayed the whole exchange: everything from the last labelled line on, breaks kept.
    private static func lastLabelledLine(in text: String, unless said: Set<String>) -> String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { String($0).trimmed() }
        guard lines.count > 1 else { return text }

        let lastLabelled = lines.lastIndex { line in
            stripLabel(from: line, unless: said) != line
        }
        guard let lastLabelled else { return text }
        return lines[lastLabelled...].joined(separator: "\n")
    }

    /// Removes a known label and its colon, unless a line of the draft opens with that label as a word.
    private static func stripLabel(from text: String, unless said: Set<String>) -> String {
        guard let colon = text.firstIndex(of: ":") else { return text }
        let label = String(text[text.startIndex..<colon]).trimmed().lowercased()
        guard labels.contains(label) else { return text }
        // The speaker said it, so it is theirs to keep.
        guard !said.contains(label) else { return text }
        return String(text[text.index(after: colon)..<text.endIndex]).trimmed()
    }

    /// Every quote pair a model wraps an answer in, straight, curly and single.
    private static let quotePairs: [(Character, Character)] = [
        ("\"", "\""), ("\u{201C}", "\u{201D}"), ("'", "'"),
        ("\u{2018}", "\u{2019}"), ("\u{00AB}", "\u{00BB}"),
    ]

    /// Removes one pair of quotes around the whole answer, unless the speaker said the quotation themselves.
    private static func stripSurroundingQuotes(_ text: String, unless spoken: String) -> String {
        guard let first = text.first, let last = text.last, text.count >= 2 else { return text }
        guard quotePairs.contains(where: { $0.0 == first && $0.1 == last }) else { return text }
        // The draft is quoted too, so the pair is the speaker's reported speech rather than the model's packaging.
        guard !isQuoted(spoken.trimmed()) else { return text }

        let inner = String(text.dropFirst().dropLast())
        // A quote around part of the answer is something the speaker meant.
        guard !containsQuote(inner, first), !containsQuote(inner, last) else { return text }
        return inner.trimmed()
    }

    /// Whether the text holds this quote mark, not counting an apostrophe between two letters.
    private static func containsQuote(_ text: String, _ mark: Character) -> Bool {
        let chars = Array(text)
        return chars.indices.contains { index in
            guard chars[index] == mark else { return false }
            guard mark == "'", index > 0, index < chars.count - 1 else { return true }
            return !(chars[index - 1].isLetter && chars[index + 1].isLetter)
        }
    }

    /// Whether the text opens and closes on one quote pair, whichever of the three it is.
    private static func isQuoted(_ text: String) -> Bool {
        guard let first = text.first, let last = text.last, text.count >= 2 else { return false }
        return quotePairs.contains { $0.0 == first && $0.1 == last }
    }

    /// Removes a Markdown wrapper around the entire reply, while retaining a wrapper the speaker said too.
    private static func stripMarkup(from text: String, unless spoken: String) -> String {
        guard let (marker, inner) = markupWrapper(of: text.trimmed()),
            markupWrapper(of: spoken.trimmed())?.marker != marker
        else { return text }
        return inner
    }

    /// The Markdown wrapper around all of `trimmed`, named by its opening marker, and the text inside it.
    private static func markupWrapper(of trimmed: String) -> (marker: String, inner: String)? {
        let lines = trimmed.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        if trimmed.hasPrefix("```"), lines.count >= 3,
            lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true
        {
            return ("```", lines.dropFirst().dropLast().joined(separator: "\n").trimmed())
        }
        if trimmed.hasPrefix("> "), lines.allSatisfy({ $0.hasPrefix("> ") }) {
            return ("> ", lines.map { String($0.dropFirst(2)) }.joined(separator: "\n").trimmed())
        }
        for marker in ["**", "__", "*", "_", "`"] where trimmed.hasPrefix(marker) && trimmed.hasSuffix(marker)
        {
            guard trimmed.count > marker.count * 2 else { continue }
            let inner = String(trimmed.dropFirst(marker.count).dropLast(marker.count))
            guard !inner.isEmpty, !inner.hasPrefix(marker), !inner.hasSuffix(marker) else { continue }
            return (marker, inner.trimmed())
        }
        return nil
    }
}

extension String {
    /// Foundation-free whitespace trim, so this module stays as testable as the core.
    func trimmed() -> String {
        String(drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
    }
}
