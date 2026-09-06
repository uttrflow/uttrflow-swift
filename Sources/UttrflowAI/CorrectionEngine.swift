// The word correction engine and the doubted runs it considers.
public import UttrflowCore
public import UttrflowDictionary

/// Proposes, never applies, dictionary words for doubted runs. See Docs/ai-correction-thresholds.md.
public struct WordCorrectionEngine: Sendable {
    /// Below this a word may be replaced; at or above it a word may corroborate, so none vouches for itself.
    public static let certaintyThreshold = 0.5

    /// Changing more than one spoken word in this many abandons the whole utterance, not just the excess.
    public static let maximumChangedInEvery = 5

    /// Makes an engine; it holds no state.
    public init() {}

    /// Every change worth arguing for, in spoken order; usually empty, and bounded by the utterance's length.
    public func proposals(
        for utterance: Utterance,
        against dictionary: PhoneticIndex,
        seeing context: AppContext = .unknown
    ) -> [WordCorrection] {
        let evidence = CorrectionEvidence(
            utterance: utterance, seeing: context, certainAt: Self.certaintyThreshold)
        let wanted = UncertainSpan.spans(in: utterance, below: Self.certaintyThreshold)
            .compactMap { proposal(for: $0, against: dictionary, given: evidence) }
        let chosen = Self.withoutOverlaps(wanted)

        // The cap counts spoken words, not proposals: replacing a run of three changes three words.
        let changed = chosen.reduce(0) { $0 + $1.wordRange.count }
        guard changed <= Self.budget(for: utterance.words.count) else { return [] }
        return chosen.sorted { $0.wordRange.lowerBound < $1.wordRange.lowerBound }
    }

    /// How many spoken words may change, never below one, or every dictation under five words is exempt.
    static func budget(for wordCount: Int) -> Int {
        max(1, wordCount / maximumChangedInEvery)
    }

    /// Every reading the dictionary offers for a heard run, and none when it already spells it exactly so.
    public static func spellings(of heard: String, in dictionary: PhoneticIndex) -> [DictionaryEntry] {
        let candidates = dictionary.candidates(soundingLike: heard)
        guard !candidates.contains(where: { $0.word == heard }) else { return [] }
        return candidates
    }

    /// The best change for one uncertain run, if there is one.
    private func proposal(
        for span: UncertainSpan, against dictionary: PhoneticIndex, given evidence: CorrectionEvidence
    ) -> WordCorrection? {
        // Condition 2.
        let candidates = Self.spellings(of: span.text, in: dictionary)

        // Candidates arrive in the index's usefulness order, so the first that earns its place is offered.
        for entry in candidates {
            // Condition 3.
            guard let reason = evidence.decisiveReason(preferring: entry.word, over: span.text)
            else { continue }
            return WordCorrection(
                heard: span.text, replacement: entry.word, wordRange: span.range,
                entryID: entry.id, reason: reason, heardConfidence: span.confidence)
        }
        return nil
    }

    /// The proposals that fit together, taken greedily from the deserving order the input arrives in.
    static func withoutOverlaps(_ proposals: [WordCorrection]) -> [WordCorrection] {
        var taken: [WordCorrection] = []
        for proposal in proposals
        where !taken.contains(where: { $0.wordRange.overlaps(proposal.wordRange) }) {
            taken.append(proposal)
        }
        return taken
    }
}

/// A run of consecutive doubted words; restated here rather than widening `UttrflowDictionary`'s own span.
struct UncertainSpan: Sendable, Equatable {
    /// Which words of the utterance the run covers.
    let range: Range<Int>
    /// The words with their spaces kept, which the phonetic index keys the same as the joined word.
    let text: String
    /// The lowest confidence in the run, which is all a run is worth.
    let confidence: Double

    /// Every run up to the index's word limit in which every word is doubted, most deserving first.
    static func spans(in utterance: Utterance, below threshold: Double) -> [UncertainSpan] {
        spans(in: utterance.words.map { ($0.text, $0.confidence) }, below: threshold)
    }

    /// The same runs over a draft, reading the words as the passes left them and skipping what nobody said.
    static func spans(in draft: Draft, below threshold: Double) -> [UncertainSpan] {
        spans(
            in: draft.words
                .filter { $0.isPresent && !$0.isLayoutMark && !$0.heard.isEmpty }
                .map { ($0.text, $0.confidence) },
            below: threshold)
    }

    /// The runs themselves, over anything that can name a word and how sure the recogniser was of it.
    static func spans(
        in words: [(text: String, confidence: Double)], below threshold: Double
    ) -> [UncertainSpan] {
        var spans: [UncertainSpan] = []
        for start in words.indices {
            for length in 1...PhoneticIndex.maximumWordsPerEntry where start + length <= words.count {
                let run = words[start..<(start + length)]
                guard run.allSatisfy({ $0.confidence < threshold }) else { break }
                spans.append(
                    UncertainSpan(
                        range: start..<(start + length),
                        text: run.map(\.text).joined(separator: " "),
                        confidence: run.reduce(1) { min($0, $1.confidence) }))
            }
        }
        return spans.sorted(by: isMoreDeserving)
    }

    /// A total order mirroring the index's own: least confident, then earliest, then longest.
    static func isMoreDeserving(_ first: UncertainSpan, _ second: UncertainSpan) -> Bool {
        if first.confidence != second.confidence { return first.confidence < second.confidence }
        if first.range.lowerBound != second.range.lowerBound {
            return first.range.lowerBound < second.range.lowerBound
        }
        return first.range.count > second.range.count
    }
}
