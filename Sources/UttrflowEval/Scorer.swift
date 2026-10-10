import UttrflowCore

/// Scores one rewrite against a reference by word overlap, since several phrasings are correct.
public enum Scorer {
    /// Scores the text as the field shows it, padded at the caret exactly as the pipeline pads it.
    public static func score(_ output: String, against reference: EvaluationCase) -> CaseScore {
        let rewritten = reference.context.insertionPoint.paddedBoundary(
            for: output, in: reference.destination)
        let produced = tokens(rewritten)
        let wanted = tokens(reference.expected)
        let wantedSurface = ClassifiedWord.words(of: reference.expected)
        let capitalisation = CapitalisationTally.measure(surfaceWords(rewritten), against: wantedSurface)
        // A phrase is one run inside one sentence, so the run it is sought in keeps the sentence ends.
        let sentences = tokens(rewritten, keepingSentenceEnds: true)
        // Matched like a guard, so a symbol requirement such as "()" is sought literally rather than always lost.
        let lost = Self.lost(reference.mustKeep, in: rewritten, tokenised: sentences)
        // A context case usually fails by adding what the context suggested, so both directions are checked.
        let invented = reference.mustNotAdd.filter { forbidden in
            isPresent(forbidden, in: rewritten, tokenised: sentences)
        }

        let alignment = WordErrorRate.measure(reference: wanted, hypothesis: produced).alignment
        let marks = PunctuationTally.measure(rewritten, against: reference.expected)
        return CaseScore(
            caseID: reference.id,
            similarity: overlap(
                spellingFolded(produced, in: reference), spellingFolded(wanted, in: reference)),
            markAccuracy: marks.accuracy,
            caseAccuracy: capitalisation.accuracy,
            keptEverythingRequired: lost.isEmpty,
            lost: lost,
            isExact: normalisedWhitespace(rewritten) == normalisedWhitespace(reference.expected),
            invented: invented,
            brokeShape: brokenShape(of: rewritten, against: reference),
            deleted: alignment.compactMap { if case .deletion(let word) = $0 { word } else { nil } },
            capitalisation: capitalisation,
            marks: marks,
            // What a clean-up that wrote everything lower case, or left the recogniser's case, would score.
            lowerCaseBaseline: CapitalisationTally.measure(
                surfaceWords(reference.expected.lowercased()), against: wantedSurface),
            spokenBaseline: CapitalisationTally.measure(
                surfaceWords(reference.spoken), against: wantedSurface)
        )
    }

    static func surfaceWords(_ text: String) -> [String] {
        var words: [String] = []
        var word = ""
        for character in text {
            if character.isLetter || character.isNumber {
                word.append(character)
            } else if !word.isEmpty {
                words.append(word)
                word = ""
            }
        }
        if !word.isEmpty { words.append(word) }
        return words
    }

    private static func normalisedWhitespace(_ text: String) -> String {
        WordTokens.words(text, .display).joined(separator: " ")
    }

    /// The beginning, ending and exact form checked literally, each named with its side so a missing anchor never reads as output.
    static func brokenShape(of rewritten: String, against reference: EvaluationCase) -> [String] {
        var broken: [String] = []
        if let head = reference.mustBeginWith, !rewritten.hasPrefix(head) {
            broken.append("begins with \"\(head)\"")
        }
        if let tail = reference.mustEndWith, !rewritten.hasSuffix(tail) {
            broken.append("ends with \"\(tail)\"")
        }
        if let exact = reference.expectedExact, rewritten != exact {
            broken.append("is exactly \"\(exact)\"")
        }
        // Each closing mark ends one sentence, and words left after the last mark are one sentence more.
        if let fewest = reference.minimumSentences {
            let marked = tokens(rewritten, keepingSentenceEnds: true)
            let closed = marked.count(where: { $0 == sentenceEnd }) + (marked.last == sentenceEnd ? 0 : 1)
            if closed < fewest { broken.append("closes \(fewest) sentences") }
        }
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

    /// Romanised Hindi has no single spelling, so its words are compared by the romaniser's sound key: "theek" is "thik".
    static func spellingFolded(_ words: [String], in reference: EvaluationCase) -> [String] {
        reference.language == .hindi ? words.map(Romaniser.soundKey) : words
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

    /// The required words a text loses, read the way every case's `mustKeep` is read, the corpus loader's check included.
    static func lost(
        _ required: [String], in text: String,
        tokenised sentences: [String]? = nil
    ) -> [String] {
        let tokenised = sentences ?? tokens(text, keepingSentenceEnds: true)
        return required.filter { !isPresent($0, in: text, tokenised: tokenised) }
    }

    /// Whether a requirement or guard is present: by word normally, literally when it has no letters or digits.
    static func isPresent(
        _ sought: String, in rewritten: String, tokenised produced: [String]
    ) -> Bool {
        let phrase = tokens(sought, keepingSentenceEnds: true)
        guard phrase.isEmpty else { return containsPhrase(phrase, in: produced) }
        // A blank phrase has nothing to look for, so it is never found: a blank guard never fires.
        guard sought.contains(where: { !$0.isWhitespace }) else { return false }
        return rewritten.contains(sought)
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
