import UttrflowCore

/// Scores one rewrite against a reference by word overlap, since several phrasings are correct.
public enum Scorer {
    public static func score(_ rewritten: String, against reference: EvaluationCase) -> CaseScore {
        let produced = tokens(rewritten)
        let wanted = tokens(reference.expected)
        // A phrase is one run inside one sentence, so the run it is sought in keeps the sentence ends.
        let sentences = tokens(rewritten, keepingSentenceEnds: true)
        // Matched on words only; a wordless requirement is reported as lost rather than quietly satisfied.
        let lost = reference.mustKeep.filter { required in
            !containsPhrase(tokens(required, keepingSentenceEnds: true), in: sentences)
        }
        // A context case usually fails by adding what the context suggested, so both directions are checked.
        let invented = reference.mustNotAdd.filter { forbidden in
            containsGuard(forbidden, in: rewritten, tokenised: sentences)
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

    /// Stands where a sentence closed, so a phrase is never read as running across the end of one.
    static let sentenceEnd = "\u{0}"

    /// Words, lowercased, with punctuation dropped, so a model is not punished for a comma.
    static func tokens(_ text: String, keepingSentenceEnds: Bool = false) -> [String] {
        var found: [String] = []
        var word = ""
        var closed = false
        var spaced = false
        // A closing mark counts only with space after it, so "p.m." is one abbreviation rather than two sentences.
        func flush() {
            guard !word.isEmpty else { return }
            if keepingSentenceEnds, closed, spaced, !found.isEmpty { found.append(sentenceEnd) }
            found.append(word)
            word = ""
            closed = false
            spaced = false
        }
        for character in text.lowercased() {
            guard !character.isLetter, !character.isNumber else {
                word.append(character)
                continue
            }
            flush()
            if ".!?".contains(character) {
                closed = true
                spaced = false
            } else if character.isWhitespace, closed {
                spaced = true
            }
        }
        flush()
        if keepingSentenceEnds, closed, !found.isEmpty { found.append(sentenceEnd) }
        return found
    }

    /// Harmonic mean of precision and recall over an aligned reading, so a word moved is not a word kept.
    static func overlap(_ produced: [String], _ wanted: [String]) -> Double {
        guard !produced.isEmpty || !wanted.isEmpty else { return 1 }
        guard !produced.isEmpty, !wanted.isEmpty else { return 0 }

        let shared = WordErrorRate.measure(reference: wanted, hypothesis: produced).hits

        let precision = Double(shared) / Double(produced.count)
        let recall = Double(shared) / Double(wanted.count)
        guard precision + recall > 0 else { return 0 }
        return 2 * precision * recall / (precision + recall)
    }

    /// Whether a `mustNotAdd` guard is present: by word normally, literally when it has no letters or digits.
    static func containsGuard(
        _ forbidden: String, in rewritten: String, tokenised produced: [String]
    ) -> Bool {
        let phrase = tokens(forbidden, keepingSentenceEnds: true)
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
}
