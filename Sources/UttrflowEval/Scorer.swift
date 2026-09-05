/// Scores one rewrite against a reference by word overlap, since several phrasings are correct.
public enum Scorer {
    public static func score(_ rewritten: String, against reference: EvaluationCase) -> CaseScore {
        let produced = tokens(rewritten)
        let wanted = tokens(reference.expected)
        // Matched on words only; a wordless requirement is reported as lost rather than quietly satisfied.
        let lost = reference.mustKeep.filter { required in
            !containsPhrase(tokens(required), in: produced)
        }
        // A context case usually fails by adding what the context suggested, so both directions are checked.
        let invented = reference.mustNotAdd.filter { forbidden in
            containsGuard(forbidden, in: rewritten, tokenised: produced)
        }

        return CaseScore(
            caseID: reference.id,
            similarity: overlap(produced, wanted),
            keptEverythingRequired: lost.isEmpty,
            lost: lost,
            isExact: produced == wanted,
            invented: invented
        )
    }

    /// Words, lowercased, with punctuation dropped, so a model is not punished for a comma.
    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    /// Harmonic mean of precision and recall over words, counting duplicates.
    static func overlap(_ produced: [String], _ wanted: [String]) -> Double {
        guard !produced.isEmpty || !wanted.isEmpty else { return 1 }
        guard !produced.isEmpty, !wanted.isEmpty else { return 0 }

        var remaining = counts(wanted)
        var shared = 0
        for token in produced where (remaining[token] ?? 0) > 0 {
            remaining[token, default: 0] -= 1
            shared += 1
        }

        let precision = Double(shared) / Double(produced.count)
        let recall = Double(shared) / Double(wanted.count)
        guard precision + recall > 0 else { return 0 }
        return 2 * precision * recall / (precision + recall)
    }

    /// Whether a `mustNotAdd` guard is present: by word normally, literally when it has no letters or digits.
    static func containsGuard(
        _ forbidden: String, in rewritten: String, tokenised produced: [String]
    ) -> Bool {
        let phrase = tokens(forbidden)
        guard phrase.isEmpty else { return containsPhrase(phrase, in: produced) }
        // A guard holding nothing has nothing to look for, and nothing is not evidence against anybody.
        guard forbidden.contains(where: { !$0.isWhitespace }) else { return false }
        return rewritten.contains(forbidden)
    }

    /// Whether `phrase` appears in `text` as a consecutive run; an empty phrase is present in nothing.
    static func containsPhrase(_ phrase: [String], in text: [String]) -> Bool {
        guard !phrase.isEmpty else { return false }
        guard phrase.count <= text.count else { return false }
        return (0...(text.count - phrase.count)).contains { start in
            Array(text[start..<start + phrase.count]) == phrase
        }
    }

    private static func counts(_ tokens: [String]) -> [String: Int] {
        tokens.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }
}
