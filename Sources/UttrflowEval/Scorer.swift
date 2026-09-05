/// Scores one rewrite against a reference.
///
/// Deliberately not exact matching: several phrasings of the same sentence are
/// correct, and a scorer that only rewards one of them would pick the model that
/// happened to agree with whoever wrote the references.
public enum Scorer {
    public static func score(_ rewritten: String, against reference: EvaluationCase) -> CaseScore {
        let produced = tokens(rewritten)
        let wanted = tokens(reference.expected)
        // Matched on words only, deliberately: punctuation is not what `mustKeep` is
        // for. Requiring a literal brace or comma to survive would punish a rewrite for
        // punctuating a sentence differently, which is the one thing this scorer has
        // decided not to measure. A wordless requirement is therefore reported as lost
        // rather than quietly satisfied, so the corpus's self-consistency test says so
        // out loud instead of the requirement doing nothing for years.
        let lost = reference.mustKeep.filter { required in
            !containsPhrase(tokens(required), in: produced)
        }
        // A context case usually fails by adding what the context suggested rather
        // than by dropping what was said, so both directions have to be checked.
        let invented = reference.mustNotAdd.filter { forbidden in
            containsGuard(forbidden, in: rewritten, tokenised: produced)
        }

        return CaseScore(
            caseID: reference.id,
            similarity: overlap(produced, wanted),
            keptEverythingRequired: lost.isEmpty,
            lost: lost,
            isExact: produced == wanted,
            invented: invented,
            brokeShape: brokenShape(of: rewritten, against: reference)
        )
    }

    /// The beginning and ending checked literally, because case and a final mark are what these cases are about.
    static func brokenShape(of rewritten: String, against reference: EvaluationCase) -> [String] {
        var broken: [String] = []
        if let head = reference.mustBeginWith, !rewritten.hasPrefix(head) { broken.append(head) }
        if let tail = reference.mustEndWith, !rewritten.hasSuffix(tail) { broken.append(tail) }
        return broken
    }

    /// Words, lowercased, with punctuation dropped.
    ///
    /// Punctuation is scored by the reference words it sits between rather than
    /// directly, so a model is not punished for a comma the reference lacks.
    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    /// Harmonic mean of precision and recall over words, counting duplicates.
    ///
    /// Recall alone would reward a model that repeats itself; precision alone would
    /// reward one that says almost nothing.
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

    /// Whether a `mustNotAdd` guard is present in the rewrite.
    ///
    /// Two paths, and they cannot be collapsed into one. Ordinary guards are matched on
    /// words so that case, spacing and neighbouring punctuation cannot hide one, and so
    /// that "cat" does not fire on "concatenate". But `tokens` throws punctuation away,
    /// so a guard made only of punctuation — "{" is the one the context cases want, to
    /// assert that a sentence about a function dictated into a chat window did not come
    /// back as code — tokenises to nothing, and nothing is trivially found in every
    /// output ever written, the case's own reference included. A guard with no letters
    /// or digits in it is therefore looked for literally in the raw text. Simplifying
    /// this back to a single tokenised call reinstates a scorer that accuses every
    /// model of inventing a brace.
    static func containsGuard(
        _ forbidden: String, in rewritten: String, tokenised produced: [String]
    ) -> Bool {
        let phrase = tokens(forbidden)
        guard phrase.isEmpty else { return containsPhrase(phrase, in: produced) }
        // A guard holding nothing at all — empty, or only whitespace — has nothing to
        // look for, and nothing is not evidence against anybody.
        guard forbidden.contains(where: { !$0.isWhitespace }) else { return false }
        return rewritten.contains(forbidden)
    }

    /// Whether `phrase` appears in `text` as a consecutive run.
    ///
    /// A multi-word requirement like "get_user" tokenises to several words, and all of
    /// them being present separately is not the same as the term surviving.
    ///
    /// A phrase with no words in it is present in nothing. The opposite answer reads as
    /// the tidier one — the empty run occurs everywhere — but it means an unusable
    /// requirement passes silently, and every caller here would rather be told.
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
