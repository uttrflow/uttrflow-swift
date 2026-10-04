import UttrflowCore

/// Scores one rewrite against a reference by word overlap, since several phrasings are correct.
public enum Scorer {
    /// Scores the text as the field shows it, padded at the caret exactly as the pipeline pads it.
    public static func score(_ output: String, against reference: EvaluationCase) -> CaseScore {
        let rewritten = reference.context.insertionPoint.paddedBoundary(for: output, in: reference.destination)
        let produced = tokens(rewritten)
        let wanted = tokens(reference.expected)
        let producedSurface = surfaceWords(rewritten)
        let wantedSurface = surfaceWords(reference.expected)
        // A phrase is one run inside one sentence, so the run it is sought in keeps the sentence ends.
        let sentences = tokens(rewritten, keepingSentenceEnds: true)
        // Matched like a guard, so a symbol requirement such as "()" is sought literally rather than always lost.
        let lost = reference.mustKeep.filter { required in
            !isPresent(required, in: rewritten, tokenised: sentences)
        }
        // A context case usually fails by adding what the context suggested, so both directions are checked.
        let invented = reference.mustNotAdd.filter { forbidden in
            isPresent(forbidden, in: rewritten, tokenised: sentences)
        }

        let alignment = WordErrorRate.measure(reference: wanted, hypothesis: produced).alignment
        return CaseScore(
            caseID: reference.id,
            similarity: overlap(produced, wanted),
            markAccuracy: markAccuracy(rewritten, reference.expected),
            caseAccuracy: caseAccuracy(producedSurface, wantedSurface),
            keptEverythingRequired: lost.isEmpty,
            lost: lost,
            isExact: normalisedWhitespace(rewritten) == normalisedWhitespace(reference.expected),
            invented: invented,
            brokeShape: brokenShape(of: rewritten, against: reference),
            deleted: alignment.compactMap { if case .deletion(let word) = $0 { word } else { nil } }
        )
    }

    /// Measures shared words whose original capitalisation is preserved.
    static func caseAccuracy(_ produced: [String], _ wanted: [String]) -> Double {
        let alignment = WordErrorRate.measure(
            reference: wanted.map { $0.lowercased() }, hypothesis: produced.map { $0.lowercased() })
        let matches = alignment.hits
        guard matches > 0 else { return 1 }
        var producedIndex = 0
        var wantedIndex = 0
        var correct = 0
        for operation in alignment.alignment {
            switch operation {
            case .match:
                if produced[producedIndex] == wanted[wantedIndex] { correct += 1 }
                producedIndex += 1
                wantedIndex += 1
            case .substitution:
                producedIndex += 1
                wantedIndex += 1
            case .deletion:
                wantedIndex += 1
            case .insertion:
                producedIndex += 1
            }
        }
        return Double(correct) / Double(matches)
    }

    /// Measures comma and sentence-end placement with an F1 score over word boundaries.
    static func markAccuracy(_ produced: String, _ wanted: String) -> Double {
        let producedMarks = marks(produced)
        let wantedMarks = marks(wanted)
        guard !producedMarks.isEmpty || !wantedMarks.isEmpty else { return 1 }
        let shared = producedMarks.intersection(wantedMarks).count
        let precision = producedMarks.isEmpty ? 0 : Double(shared) / Double(producedMarks.count)
        let recall = wantedMarks.isEmpty ? 0 : Double(shared) / Double(wantedMarks.count)
        guard precision + recall > 0 else { return 0 }
        return 2 * precision * recall / (precision + recall)
    }

    private static func marks(_ text: String) -> Set<String> {
        var result: Set<String> = []
        var word = ""
        var wordCount = 0
        func flush() {
            guard !word.isEmpty else { return }
            wordCount += 1
            word = ""
        }
        for character in text {
            if character.isLetter || character.isNumber {
                word.append(character)
                continue
            }
            flush()
            if character == "," { result.insert("\(wordCount):comma") }
            if ".!?".contains(character) { result.insert("\(wordCount):sentence") }
        }
        flush()
        return result
    }

    private static func surfaceWords(_ text: String) -> [String] {
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
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The beginning, ending and exact form checked literally, each named with its side so a missing anchor never reads as output.
    static func brokenShape(of rewritten: String, against reference: EvaluationCase) -> [String] {
        var broken: [String] = []
        if let head = reference.mustBeginWith, !rewritten.hasPrefix(head) { broken.append("begins with \"\(head)\"") }
        if let tail = reference.mustEndWith, !rewritten.hasSuffix(tail) { broken.append("ends with \"\(tail)\"") }
        if let exact = reference.expectedExact, rewritten != exact {
            broken.append("is exactly \"\(exact)\"")
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
