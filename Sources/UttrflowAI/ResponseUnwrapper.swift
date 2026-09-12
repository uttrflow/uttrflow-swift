// Unwraps a model's reply, with the whitespace trim it relies on.
/// Strips a bare label or whole-answer quotes from a model's reply. See Docs/ai-model-output.md.
public enum ResponseUnwrapper {
    /// Labels a model echoes from the worked examples; a sentence is not a label and is left for the guard.
    private static let labels = [
        "cleaned", "output", "result", "text", "response", "answer", "corrected", "rewritten",
    ]

    /// The answer without its wrapper; a label the speaker said themselves ("Output: ship it") stays.
    public static func unwrap(_ rewritten: String, spoken: String) -> String {
        var text = lastLabelledLine(in: rewritten.trimmed(), unless: spoken)
        text = stripLabel(from: text, unless: spoken)
        text = stripSurroundingQuotes(text, unless: spoken)
        // A model that wrote `Cleaned: "…"` needs both removed, in that order.
        return stripLabel(from: text, unless: spoken).trimmed()
    }

    /// The answer from a reply that replayed the whole exchange: everything from the last labelled line on.
    private static func lastLabelledLine(in text: String, unless spoken: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmed() }
        guard lines.count > 1 else { return text }

        let lastLabelled = lines.lastIndex { line in
            stripLabel(from: line, unless: spoken) != line
        }
        guard let lastLabelled else { return text }
        return lines[lastLabelled...].joined(separator: " ")
    }

    /// Removes a known label and its colon, unless the speaker's own words begin with that label.
    private static func stripLabel(from text: String, unless spoken: String) -> String {
        guard let colon = text.firstIndex(of: ":") else { return text }
        let label = String(text[text.startIndex..<colon]).trimmed().lowercased()
        guard labels.contains(label) else { return text }
        // The speaker said it, so it is theirs to keep.
        guard !spoken.trimmed().lowercased().hasPrefix(label) else { return text }
        return String(text[text.index(after: colon)..<text.endIndex]).trimmed()
    }

    /// Every quote pair a model wraps an answer in, straight, curly and single.
    private static let quotePairs: [(Character, Character)] = [
        ("\"", "\""), ("\u{201C}", "\u{201D}"), ("'", "'"),
    ]

    /// Removes one pair of quotes around the whole answer, unless the speaker said the quotation themselves.
    private static func stripSurroundingQuotes(_ text: String, unless spoken: String) -> String {
        guard let first = text.first, let last = text.last, text.count >= 2 else { return text }
        guard quotePairs.contains(where: { $0.0 == first && $0.1 == last }) else { return text }
        // The draft is quoted too, so the pair is the speaker's reported speech rather than the model's packaging.
        guard !isQuoted(spoken.trimmed()) else { return text }

        let inner = String(text.dropFirst().dropLast())
        // A quote around part of the answer is something the speaker meant.
        guard !inner.contains(first), !inner.contains(last) else { return text }
        return inner.trimmed()
    }

    /// Whether the text opens and closes on one quote pair, whichever of the three it is.
    private static func isQuoted(_ text: String) -> Bool {
        guard let first = text.first, let last = text.last, text.count >= 2 else { return false }
        return quotePairs.contains { $0.0 == first && $0.1 == last }
    }
}

extension String {
    /// Foundation-free whitespace trim, so this module stays as testable as the core.
    func trimmed() -> String {
        String(drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
    }
}
