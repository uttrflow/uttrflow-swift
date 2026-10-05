public import UttrflowCore
import UttrflowDictionary

// The verdict on a rewrite, and the guard that reaches it.
/// Whether a rewrite may be shown to the user.
public enum GuardVerdict: Sendable, Equatable {
    /// The rewrite may be shown.
    case accepted
    /// The rewrite is refused, with the reason a log can show and the kind a pasted report may carry.
    case rejected(reason: String, kind: RefusalKind)

    public var isAccepted: Bool { self == .accepted }
}

/// Checks that a model tidied the words rather than replacing them. See Docs/ai-model-output.md.
public struct MeaningPreservationGuard: Sendable {
    /// A rewrite may grow — punctuation, expanded contractions — but not by this much.
    static let maximumGrowthFactor = 2.0
    /// Below this fraction of the original words the model replaced rather than tidied.
    static let minimumRetainedFraction = 0.4
    /// Utterances this short skip the retention floor ("um yes" to "Yes."); at six, "Paris" slipped through.
    static let shortUtteranceWords = 3

    /// Openings that mean the model is chatting rather than tidying.
    static let preambles = [
        "here is", "here's", "sure,", "certainly", "of course", "i've", "i have",
        "the corrected", "the cleaned", "cleaned:", "output:", "result:",
    ]

    /// Makes a guard; it holds no state.
    public init() {}

    /// Judges the rewrite against the kept words, the words a pass took out beyond its grant, the readings offered, the echo a pass took back, and the layout allowed.
    public func verdict(
        draft: Draft, rewritten: String, offering doubtful: [DoubtfulSpan] = [], echoed: String = "",
        layout: LayoutPolicy = [.paragraphs, .lists],
        grammar: GrammarPolicy = .repair,
        grants: [PassID: RemovalGrant] = CleaningPipeline.standard.grants
    ) -> GuardVerdict {
        let rewritten = Self.respellingClockTimes(rewritten, as: draft.text)
        let excusingPreamble = Self.rewriteStartsWithOfferedReading(
            draft: draft, rewritten: rewritten, offering: doubtful)
        if case .rejected(let reason, let kind) = Self.textVerdict(
            original: draft.text, rewritten: rewritten, excusingPreamble: excusingPreamble)
        {
            return .rejected(reason: reason, kind: kind)
        }
        if case .rejected(let reason, let kind) = Self.spokenPunctuationVerdict(
            draft: draft, rewritten: rewritten)
        {
            return .rejected(reason: reason, kind: kind)
        }
        let restored = Self.restored(RemovalAudit.unauthorised(in: draft, grants: grants))
        if case .rejected(let reason, let kind) = Self.removalVerdict(
            restored, kept: draft.text, rewritten: rewritten, echoed: echoed)
        {
            return .rejected(reason: reason, kind: kind)
        }
        let alignment = RewriteAlignment(kept: draft.text, rewritten: rewritten)
        let readings = Self.readingVerdict(doubtful, in: alignment)
        if case .rejected(let reason, let kind) = readings.verdict {
            return .rejected(reason: reason, kind: kind)
        }
        if case .rejected(let reason, let kind) = Self.confidentHomophoneVerdict(draft, aligned: alignment) {
            return .rejected(reason: reason, kind: kind)
        }
        if case .rejected(let reason, let kind) = Self.layoutVerdict(
            kept: draft.text, rewritten: rewritten, layout: layout)
        {
            return .rejected(reason: reason, kind: kind)
        }
        return Self.grammarVerdict(
            alignment, excusing: readings.excused, echoed: echoed, allowing: doubtful,
            restoring: restored.map(\.token), policy: grammar)
    }

    /// Allows a chat-like opening only when it is the offered reading of the doubtful first run.
    private static func rewriteStartsWithOfferedReading(
        draft: Draft, rewritten: String, offering doubtful: [DoubtfulSpan]
    ) -> Bool {
        guard let first = doubtful.first,
            let heard = draft.text.range(of: first.heard, options: [.caseInsensitive]),
            draft.text[..<heard.lowerBound].allSatisfy(\.isWhitespace),
            first.candidates.contains(where: { candidate in
                rewritten.range(of: candidate.spelling, options: [.caseInsensitive, .anchored]) != nil
            })
        else { return false }
        return true
    }

    /// Refuses a rewrite that drops or substitutes punctuation a pass wrote from spoken instructions.
    static func spokenPunctuationVerdict(draft: Draft, rewritten: String) -> GuardVerdict {
        let marks = Set(SpokenCommands.marks.flatMap { Array($0.text) } + Array("()[]{}"))
        var required: [Character: Int] = [:]
        for word in draft.words {
            for edit in word.edits where edit.by == .spokenPunctuation && edit.kind == .replaced {
                guard !edit.to.contains("@") else { continue }
                for mark in marks {
                    let added = edit.to.filter { $0 == mark }.count - edit.from.filter { $0 == mark }.count
                    if added > 0 { required[mark, default: 0] += added }
                }
            }
        }
        for (mark, count) in required where rewritten.filter({ $0 == mark }).count < count {
            return .rejected(
                reason: "the rewrite dropped a spoken punctuation mark", kind: .layout)
        }
        return .accepted
    }

    /// Refuses a sound-alike substitution when the recogniser was sure of the kept word.
    private static func confidentHomophoneVerdict(_ draft: Draft, aligned: RewriteAlignment) -> GuardVerdict {
        guard draft.confidencesAreReal else { return .accepted }
        let heard = draft.words
            .filter { $0.isPresent && !$0.isLayoutMark && !$0.heard.isEmpty }
            .flatMap { word in grammarTokens(word.text).map { (token: $0, confidence: word.confidence) } }
        for change in aligned.changes {
            for index in change.kept where index < heard.count {
                let token = aligned.kept[index]
                guard heard[index].confidence >= WordCorrectionEngine.certaintyThreshold else { continue }
                if change.rewritten.contains(where: {
                    Homophones.share(token.matching, aligned.rewritten[$0].matching)
                }) {
                    return .rejected(
                        reason: "the rewrite replaced high-confidence '\(token.text)' with a sound-alike",
                        kind: .lostWord)
                }
            }
        }
        return .accepted
    }

    /// The content words and negations among removals no grant covers, each with the pass that took it.
    static func restored(_ removals: [UnauthorisedRemoval]) -> [(pass: PassID, token: GrammarToken)] {
        removals.flatMap { removal in
            grammarTokens(removal.text)
                .filter { $0.isPlain && (isContent($0) || isNegation($0.matching)) }
                .map { (removal.pass, $0) }
        }
    }

    /// Refuses a rewrite that leaves out a word a pass removed without the grant to, since the passes alone cannot answer for it.
    static func removalVerdict(
        _ restored: [(pass: PassID, token: GrammarToken)], kept: String, rewritten: String, echoed: String
    ) -> GuardVerdict {
        let written = (grammarTokens(echoed) + grammarTokens(rewritten)).filter(\.isPlain)
        var negations = negators(in: grammarTokens(kept))
        let romanisedHindiContext = hasRomanisedHindiContext(grammarTokens(kept) + written)
        for (pass, token) in restored {
            let negates = Self.isNegation(token.matching)
            if negates { negations += 1 }
            let present =
                negates
                ? negators(in: written) >= negations
                : written.contains {
                    survives(token.matching, as: $0, allowingRomanisedHindiSpellings: romanisedHindiContext)
                }
            guard present else {
                return .rejected(
                    reason: "the \(pass) step took out '\(token.text)' and the rewrite does not put it back",
                    kind: .removedWordNotRestored)
            }
        }
        return .accepted
    }

    /// The readings the rewrite wrote where a doubtful run stood, so the entries that taught them are counted used.
    public func readingsTaken(
        draft: Draft, rewritten: String, offering doubtful: [DoubtfulSpan]
    ) -> [Reading] {
        guard !doubtful.isEmpty else { return [] }
        return Self.readingVerdict(doubtful, in: RewriteAlignment(kept: draft.text, rewritten: rewritten))
            .taken
    }

    /// A doubtful run may be written where it stands as it was heard or as a reading offered for it, inflected or not, and as nothing else.
    static func readingVerdict(
        _ doubtful: [DoubtfulSpan], in alignment: RewriteAlignment
    ) -> (verdict: GuardVerdict, excused: Set<Int>, taken: [Reading]) {
        var excused: Set<Int> = []
        var taken: [Reading] = []
        guard !doubtful.isEmpty else { return (.accepted, excused, taken) }
        for span in doubtful {
            for (ordinal, place) in alignment.keptRuns(spelled: DoubtfulSpan.closedUp(span.heard))
                .enumerated()
            {
                let touched = alignment.changes.filter { $0.kept.overlaps(place) }
                // A run the rewrite left where it stood is the run as it was heard, and needs no reading.
                guard let first = touched.first, let last = touched.last else { continue }
                let start = min(place.lowerBound, first.kept.lowerBound)
                let end = max(place.upperBound, last.kept.upperBound)
                // A change reaching past the run took its neighbours with it, so they are expected here too.
                let before = alignment.keptSpelling(of: start..<place.lowerBound)
                let after = alignment.keptSpelling(of: place.upperBound..<end)
                // The rewrite may inflect the run it was given — "payment sheets" for "payment sheet" — and change it no further.
                func writes(_ reading: String) -> Bool {
                    let wanted = DoubtfulSpan.closedUp(reading)
                    return WordForms.inflections(of: wanted).union([wanted]).map { before + $0 + after }
                        .contains(alignment.standing(in: start..<end))
                }
                let offered = span.candidates.filter { writes($0.spelling) }
                // A later mention of the same words was offered nothing, so it stands as it was heard.
                guard span.isDoubted(at: ordinal) else {
                    guard
                        Self.reading(
                            among: offered, heard: span.heard,
                            standing: alignment.standingAsWritten(in: start..<end)) == nil
                    else {
                        return (
                            .rejected(
                                reason:
                                    "the rewrite read '\(span.heard)' as a reading offered for another mention",
                                kind: .unofferedReading),
                            excused, taken
                        )
                    }
                    continue
                }
                guard writes(span.heard) || !offered.isEmpty else {
                    return (
                        .rejected(
                            reason: "the rewrite read '\(span.heard)' as a word it was not offered",
                            kind: .unofferedReading),
                        excused, taken
                    )
                }
                if let reading = Self.reading(
                    among: offered, heard: span.heard, standing: alignment.standingAsWritten(in: start..<end))
                {
                    taken.append(reading)
                }
                // A reading rightly written here is the one substitution the survival check must let past.
                for change in touched { excused.formUnion(change.kept.clamped(to: place)) }
            }
        }
        return (.accepted, excused, taken)
    }

    /// The offered reading written in the run's place, told from the heard words by its capitals and spaces when it closes up alike.
    private static func reading(
        among offered: [Reading], heard: String, standing written: String
    ) -> Reading? {
        let asHeard = RewriteAlignment.asWritten(heard)
        return offered.first { reading in
            let spelled = RewriteAlignment.asWritten(reading.spelling)
            // Capitals alone are what a sentence gives its first word, so they are no sign the model chose the reading.
            guard spelled.lowercased() != asHeard.lowercased() else { return false }
            return written.contains(spelled)
        }
    }

    /// The same judgement over two texts, which is how a test states one.
    static func candidateVerdict(
        _ doubtful: [DoubtfulSpan], kept: String, rewritten: String
    ) -> GuardVerdict {
        readingVerdict(doubtful, in: RewriteAlignment(kept: kept, rewritten: rewritten)).verdict
    }

    /// Whether a reading is written out as whole words: `PaymentSheet` or "payment sheets" for "payment sheet", never "our time" inside "four times".
    static func isWritten(_ reading: String, in rewritten: String) -> Bool {
        let wanted = DoubtfulSpan.closedUp(reading)
        guard !wanted.isEmpty else { return false }
        let (written, begins, ends) = closedUpEdges(rewritten)
        // The rewrite may inflect the run it was given — "payment sheets" for "payment sheet" — and change it no further.
        let forms = WordForms.inflections(of: wanted).union([wanted])
        return begins.contains { start in
            forms.contains { form in
                let end = start + form.count
                return end <= written.count && ends.contains(end)
                    && String(written[start..<end]) == form
            }
        }
    }

    /// A text closed up, with the places a word begins and ends, reading a camel hump as an edge like `spelledInto`.
    static func closedUpEdges(_ text: String) -> (written: [Character], begins: Set<Int>, ends: Set<Int>) {
        var written: [Character] = []
        var begins: Set<Int> = []
        var ends: Set<Int> = [0]
        var previous: Character?
        for character in text {
            guard character.isLetter || character.isNumber else {
                previous = character
                continue
            }
            // A word opens at the start, after anything that is not a letter, and at a capital.
            if (previous.map { !$0.isLetter } ?? true) || character.isUppercase {
                begins.insert(written.count)
                ends.insert(written.count)
            }
            if !character.isLetter { ends.insert(written.count) }  // A digit closes the word before it.
            written += DoubtfulSpan.closedUp(String(character))
            previous = character
        }
        ends.insert(written.count)
        return (written, begins, ends)
    }

    /// Spells each `H:MM` back as the kept `H.MM` that `NumberFormsPass` would itself write as that clock.
    static func respellingClockTimes(_ rewritten: String, as kept: String) -> String {
        let clocks = NumberFormsPass.dottedClockTimes(in: kept)
        guard !clocks.isEmpty else { return rewritten }
        var result = rewritten
        for dotted in clocks {
            let colon = dotted.replacingOccurrences(of: ".", with: ":")
            result = result.replacingOccurrences(
                of: "(?<![\\d.:])\(colon)(?![\\d:]|\\.\\d)", with: dotted, options: .regularExpression)
        }
        return result
    }

    /// Aux verbs the rewrite can still contract to the same word; a dropped or substituted one is a rewrite.
    static let auxContractionRoots: Set<String> = [
        "do", "does", "did",
        "is", "are", "was", "were",
        "have", "has", "had",
        "will", "would", "shall", "should",
        "can", "could", "may", "might", "must",
    ]

    /// Detects romanised Hindi from a negation or a known verb form outside the ambiguous spelling pairs.
    static func hasRomanisedHindiContext(_ tokens: [GrammarToken]) -> Bool {
        tokens.contains { token in
            let word = token.matching
            return isNegation(word) || WordForms.hindiVerbStems.contains(word)
                || WordForms.hindiVerbStems.contains { WordForms.hindiForms(of: $0).contains(word) }
        }
    }

    /// How many words in `tokens` turn a sentence's meaning around.
    static func negators(in tokens: [GrammarToken]) -> Int {
        tokens.filter { isNegation($0.matching) }.count
    }

    /// Whether a word reverses a sentence, read without its apostrophes so "doesn't" and "doesnt" are one negation.
    static func isNegation(_ word: String) -> Bool {
        negatingWords.contains(word.replacingOccurrences(of: "'", with: ""))
    }

    /// The words that reverse a sentence, apostrophes aside; dropping or adding one is the worst edit the model can make.
    static let negatingWords: Set<String> =
        englishNegations.union(hindiNegations)

    /// English, with the apostrophes already out, which is the form `matching` carries.
    static let englishNegations: Set<String> = [
        "not", "no", "never", "none", "nothing", "nobody", "nowhere", "neither", "nor", "cannot",
        "dont", "doesnt", "didnt", "wont", "wouldnt", "cant", "couldnt", "shouldnt", "isnt",
        "arent", "wasnt", "werent", "hasnt", "havent", "hadnt", "mustnt", "aint", "neednt",
    ]

    /// Hindi in both scripts, since the prompt asks the model to romanise and the negation must survive that.
    static let hindiNegations: Set<String> = HindiWords.negations.union([
        "\u{0928}\u{0939}\u{0940}\u{0902}", "\u{0928}\u{093E}", "\u{092E}\u{0924}",
    ])

    /// Function words added plus removed, counted as multisets over the supplied runs.
    static func functionWordChurn(_ kept: [GrammarToken], _ rewritten: [GrammarToken]) -> Int {
        func counts(_ tokens: [GrammarToken]) -> [String: Int] {
            var result: [String: Int] = [:]
            for token in tokens where token.isPlain && !isContent(token) {
                result[token.lookup, default: 0] += 1
            }
            return result
        }
        let before = counts(kept)
        let after = counts(rewritten)
        return Set(before.keys).union(after.keys).reduce(0) { $0 + abs((before[$1] ?? 0) - (after[$1] ?? 0)) }
    }

    /// Words a sentence of dictation runs to before a text without any sentence end counts as unpunctuated.
    static let wordsPerSentenceEnd = 40

    /// Sentences the churn allowance is for: those the rewrite closes, or those the input's length implies, whichever is more.
    static func churnSentences(_ alignment: RewriteAlignment) -> Int {
        let byLength = (words(in: alignment.keptText) + wordsPerSentenceEnd - 1) / wordsPerSentenceEnd
        return max(sentenceCount(alignment.rewrittenText), byLength)
    }

    /// Whitespace-separated words in the text.
    static func words(in text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }

    /// Sentences in the rewrite, counted by closing marks followed by space or end, never below one.
    static func sentenceCount(_ text: String) -> Int { max(1, sentenceEnds(text)) }

    /// Closing marks followed by space or end, which may be none.
    static func sentenceEnds(_ text: String) -> Int {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        return words.indices.count { index in
            Abbreviations.endsSentence(words[index], followedBy: words.dropFirst(index + 1).first)
        }
    }
}
