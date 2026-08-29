/// Removes the wrapper a model puts around an otherwise correct answer.
///
/// Few-shot examples teach the task by showing `Cleaned: "…"`, and models reasonably
/// echo that shape. The words inside are right; only the packaging is wrong. Without
/// this, a perfectly good rewrite is thrown away by the meaning guard as though the
/// model had started chatting — which is exactly what happened the first time a local
/// model was measured, and it looked like the model was terrible.
///
/// Deliberately narrow: it strips a bare label from a known list, and matched quotes
/// around the whole answer. A sentence like "Sure, here is the text:" is *not* a bare
/// label and still gets rejected, because that really is the model chatting.
public enum ResponseUnwrapper {
    private static let labels = [
        "cleaned", "output", "result", "text", "response", "answer", "corrected", "rewritten",
    ]

    /// - Parameters:
    ///   - rewritten: What the model returned.
    ///   - spoken: What the user actually said. A label is only removed when the
    ///     speaker did not say it themselves, so dictating "Output: ship it" survives.
    /// - Returns: The answer without its wrapper.
    public static func unwrap(_ rewritten: String, spoken: String) -> String {
        var text = lastLabelledLine(in: rewritten.trimmed(), unless: spoken)
        text = stripLabel(from: text, unless: spoken)
        text = stripSurroundingQuotes(text)
        // A model that wrote `Cleaned: "…"` needs both removed, in that order.
        return stripLabel(from: text, unless: spoken).trimmed()
    }

    /// Picks the answer out of a reply that replayed the whole exchange.
    ///
    /// Some models echo the worked example in full — the prompt back, then their
    /// answer under its label. Everything before the last labelled line is the echo.
    /// Observed from a 4B model, whose real output was correct and whose score was not.
    private static func lastLabelledLine(in text: String, unless spoken: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmed() }
        guard lines.count > 1 else { return text }

        let lastLabelled = lines.lastIndex { line in
            stripLabel(from: line, unless: spoken) != line
        }
        guard let lastLabelled else { return text }
        return lines[lastLabelled...].joined(separator: " ")
    }

    private static func stripLabel(from text: String, unless spoken: String) -> String {
        guard let colon = text.firstIndex(of: ":") else { return text }
        let label = String(text[text.startIndex..<colon]).trimmed().lowercased()
        guard labels.contains(label) else { return text }
        // The speaker said it, so it is theirs to keep.
        guard !spoken.trimmed().lowercased().hasPrefix(label) else { return text }
        return String(text[text.index(after: colon)..<text.endIndex]).trimmed()
    }

    private static func stripSurroundingQuotes(_ text: String) -> String {
        let pairs: [(Character, Character)] = [("\"", "\""), ("\u{201C}", "\u{201D}"), ("'", "'")]
        guard let first = text.first, let last = text.last, text.count >= 2 else { return text }
        guard pairs.contains(where: { $0.0 == first && $0.1 == last }) else { return text }

        let inner = String(text.dropFirst().dropLast())
        // Only a quote around the whole answer is packaging; one around part of it is
        // something the speaker meant.
        guard !inner.contains(first), !inner.contains(last) else { return text }
        return inner.trimmed()
    }
}

extension String {
    /// Foundation-free whitespace trim, so this module stays as testable as the core.
    func trimmed() -> String {
        String(drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
    }
}
