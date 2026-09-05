public import UttrflowCore
public import UttrflowDictionary

/// Replaces a word that does not belong in a sentence, and otherwise does nothing.
///
/// The second half of that sentence is the feature. The owner asked for a wrong word to
/// be fixed and was emphatic about the other side of it — "otherwise all good things also
/// getting changed would be a bad design" — and those two pull against each other, so the
/// resolution has to be written down rather than tuned. **The default is to do nothing.**
///
/// Three conditions, all of which must hold before a single word moves.
///
/// 1. *The recogniser was unsure* — every word in the run scored below
///    ``certaintyThreshold``.
/// 2. *A candidate exists* — the phonetic index already answers this, and answers it in
///    constant time however large the dictionary grows.
/// 3. *The sentence improves* — ``CorrectionEvidence`` scores both readings against the
///    situation and the candidate must win by a clear margin.
///
/// Each condition alone is a different disaster, which is why all three are required.
/// Condition one alone rewrites constantly, because recognisers are unsure all the time.
/// Condition two alone is precisely how a correct-but-rare word gets destroyed: "clawed"
/// and "Claude" sound identical and the index cannot tell you which was meant. Condition
/// three alone would be a language model guessing at words it has never seen.
///
/// Nothing here is applied. The engine returns proposals and the caller decides, because
/// only the caller knows what the text is for — and because a change nobody can see is a
/// change nobody can undo.
public struct WordCorrectionEngine: Sendable {
    /// Below this the recogniser was guessing; at or above it, it was sure.
    ///
    /// One number doing two jobs, deliberately. It is both the line under which a word may
    /// be replaced and the line at or above which a word may corroborate a replacement,
    /// and because those two sets are exact complements a mis-heard word cannot vouch for
    /// itself.
    ///
    /// A half. Speech engines disagree wildly about what their scores mean, so a number
    /// tuned against one of them would be wrong for the next; a half is the point at which
    /// a recogniser is claiming to be more right than wrong, on anybody's scale.
    public static let certaintyThreshold = 0.5

    /// One word in five, and not one more.
    ///
    /// The second hard stop. An engine that wants to change a third of an utterance has
    /// not found a third of a sentence's worth of mistakes, it has misread the sentence —
    /// and the honest response to that is to leave the whole thing alone rather than to
    /// apply the first few and hope.
    public static let maximumChangedInEvery = 5

    public init() {}

    /// Every change worth arguing for, in the order the words were spoken.
    ///
    /// Empty is the expected answer and the commonest one. An utterance with nothing wrong
    /// in it, or nothing corroborated, or too much wrong at once, all come back empty and
    /// the caller types what was heard.
    ///
    /// The work is bounded by the utterance, not by the dictionary: at most three runs per
    /// spoken word, each costing two hash probes into buckets the index caps. A user with
    /// fifty thousand words pays what a user with ten pays.
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

        // The cap counts spoken words rather than proposals, because replacing a run of
        // three with one word changes three words of what the user said.
        let changed = chosen.reduce(0) { $0 + $1.wordRange.count }
        guard changed <= Self.budget(for: utterance.words.count) else { return [] }
        return chosen.sorted { $0.wordRange.lowerBound < $1.wordRange.lowerBound }
    }

    /// How many spoken words this utterance may lose.
    ///
    /// The floor of one is not a softening of the rule but a refusal to round it into a
    /// different one: without it every dictation shorter than five words would be exempt
    /// from correction entirely, which is not "at most one in five", it is "never" — and
    /// short dictations are most of them.
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

        // Ordered by how useful the index judges them, so the first that earns its place
        // is the one to offer and the result does not depend on iteration luck.
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

    /// The proposals that fit together, best first.
    ///
    /// Two runs can both want the same word — "s q l" and "q l" are both runs — and the
    /// user can only be shown one answer for it. The input arrives in deserving order, so
    /// taking greedily is taking the least confident, earliest, longest run each time.
    static func withoutOverlaps(_ proposals: [WordCorrection]) -> [WordCorrection] {
        var taken: [WordCorrection] = []
        for proposal in proposals
        where !taken.contains(where: { $0.wordRange.overlaps(proposal.wordRange) }) {
            taken.append(proposal)
        }
        return taken
    }
}

/// A run of consecutive words the recogniser was unsure of, all the way through.
///
/// `UttrflowDictionary` has this shape already, in the `SpokenSpan` its own lookup is built
/// from, but that type and the runs it makes are internal to that module. Three fields
/// restated here is the cheaper of the two costs — the alternative is widening a
/// neighbouring module's surface for one caller, and the runs are not the same runs
/// anyway: those are ordered for a candidate budget, these are filtered by a hard stop
/// this engine owns.
struct UncertainSpan: Sendable, Equatable {
    let range: Range<Int>
    /// The words with their spaces left in, which is what the phonetic index wants:
    /// a space makes no sound, so "payment sheet" keys identically to `PaymentSheet`.
    let text: String
    /// The lowest confidence in the run, which is all a run is worth.
    let confidence: Double

    /// Every run of up to ``PhoneticIndex/maximumWordsPerEntry`` words in which the
    /// recogniser was unsure of *every* word, most deserving first.
    ///
    /// Every word, not the run's average or its minimum: a run containing one confidently
    /// heard word cannot be replaced without overwriting that word, and the first hard
    /// stop is that a confident hearing is never overwritten. Once a run hits a confident
    /// word, every longer run from the same start contains it too, so the search stops
    /// there rather than testing them.
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

    /// A total order, so the same utterance always produces the same proposals. It mirrors
    /// the index's own ordering — least confident first, then earliest, then longest —
    /// because the two must not disagree about which run mattered most.
    static func isMoreDeserving(_ first: UncertainSpan, _ second: UncertainSpan) -> Bool {
        if first.confidence != second.confidence { return first.confidence < second.confidence }
        if first.range.lowerBound != second.range.lowerBound {
            return first.range.lowerBound < second.range.lowerBound
        }
        return first.range.count > second.range.count
    }
}
