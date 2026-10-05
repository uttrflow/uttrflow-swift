// The word correction engine and the doubted runs it considers.
public import UttrflowCore
public import UttrflowDictionary

/// Proposes, never applies, dictionary words for doubted runs. See Docs/ai-correction-thresholds.md.
public struct WordCorrectionEngine: Sendable {
    /// Below this a word may be replaced; at or above it a word may corroborate, so none vouches for itself.
    public static let certaintyThreshold = 0.5

    /// Changing more than one spoken word in this many abandons the whole utterance, not just the excess.
    static let maximumChangedInEvery = 5

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
        let recased = Self.recasings(of: utterance, against: dictionary)
        let chosen = Self.withoutOverlaps(
            wanted.filter { proposal in
                !recased.contains { $0.wordRange.overlaps(proposal.wordRange) }
            })

        // Each dictionary entry is one proposal, even when it replaces a multi-word run.
        guard chosen.count <= Self.budget(for: utterance.words.count) else { return recased }
        return (recased + chosen).sorted { $0.wordRange.lowerBound < $1.wordRange.lowerBound }
    }

    /// Every run whose letters are an entry's in another case, whatever its score; it changes no word, so no budget.
    static func recasings(of utterance: Utterance, against dictionary: PhoneticIndex) -> [WordCorrection] {
        let words = utterance.words
        var found: [WordCorrection] = []
        var start = 0
        while start < words.count {
            let longest = (1...PhoneticIndex.maximumWordsPerEntry).reversed().lazy
                .filter { start + $0 <= words.count }
                .compactMap { recasing(of: words[start..<(start + $0)], at: start, against: dictionary) }
                .first
            guard let longest else {
                start += 1
                continue
            }
            found.append(longest)
            start = longest.wordRange.upperBound
        }
        return found
    }

    /// The entry's spelling for one run when the run's letters match it exactly bar case, with edge punctuation kept.
    private static func recasing(
        of run: ArraySlice<SpokenWord>, at start: Int, against dictionary: PhoneticIndex
    ) -> WordCorrection? {
        let heard = run.map(\.text).joined(separator: " ")
        let isEdge: (Character) -> Bool = { !$0.isLetter && !$0.isNumber }
        let lead = heard.prefix(while: isEdge)
        let trail = String(heard.reversed().prefix(while: isEdge).reversed())
        guard lead.count + trail.count < heard.count else { return nil }
        let core = String(heard.dropFirst(lead.count).dropLast(trail.count))
        guard let entry = dictionary.entries(speltAs: core).first, entry.word != core else { return nil }
        return WordCorrection(
            heard: heard, replacement: lead + entry.word + trail,
            wordRange: start..<(start + run.count), entryID: entry.id, reason: .spelledAsInDictionary,
            heardConfidence: run.map(\.confidence).min() ?? 1)
    }

    /// How many spoken words may change, never below one, or every dictation under five words is exempt.
    static func budget(for wordCount: Int) -> Int {
        max(1, wordCount / maximumChangedInEvery)
    }

    /// Every reading the dictionary offers for a heard run, and none when it already spells it exactly so.
    public static func spellings(of heard: String, in dictionary: PhoneticIndex) -> [DictionarySpelling] {
        let whole = dictionary.candidates(soundingLike: heard)
        guard !whole.contains(where: { $0.word == heard }) else { return [] }
        var found = whole.map { DictionarySpelling(entry: $0, ending: "", heard: heard) }
        var words = heard.split(separator: " ").map(String.init)
        guard let last = words.popLast(), let split = WordForms.nameEnding(of: last) else { return found }
        // A name said with a plural or possessive ending is looked up without it, and the ending is reattached verbatim.
        let name = (words + [split.name]).joined(separator: " ")
        let named = dictionary.candidates(soundingLike: name)
        guard !named.contains(where: { $0.word == name }) else { return [] }
        let taken = Set(whole.map(\.id))
        found += named.filter { !taken.contains($0.id) }.map {
            DictionarySpelling(entry: $0, ending: split.ending, heard: name)
        }
        return found
    }

    /// The best change for one uncertain run, if there is one.
    private func proposal(
        for span: UncertainSpan, against dictionary: PhoneticIndex, given evidence: CorrectionEvidence
    ) -> WordCorrection? {
        // Condition 2.
        let candidates = Self.spellings(of: span.text, in: dictionary)

        // Candidates arrive in the index's usefulness order, so the first that earns its place is offered.
        for candidate in candidates {
            // Condition 3.
            guard Self.spells(candidate.entry, asHeard: candidate.heard),
                let reason = evidence.decisiveReason(preferring: candidate.entry.word, over: candidate.heard)
            else { continue }
            return WordCorrection(
                heard: span.text, replacement: candidate.word, wordRange: span.range,
                entryID: candidate.entry.id, reason: reason, heardConfidence: span.confidence)
        }
        return nil
    }

    /// Whether an entry writes out or reads as a multi-word run, or a one-word reading opens alike.
    static func spells(_ entry: DictionaryEntry, asHeard heard: String) -> Bool {
        if WordShape.words(heard).count > 1 {
            return MeaningPreservationGuard.isWritten(heard, in: entry.word)
                || MeaningPreservationGuard.isWritten(heard, in: entry.soundsLike)
                || reads(entry, as: heard)
        }
        // Either the spelling or the pronunciation the user wrote for it, which is what that field is for.
        return [entry.word, entry.soundsLike].contains {
            ReadingRestraint.closedUp($0) == ReadingRestraint.closedUp(heard)
                || ReadingRestraint.opensAlike($0, heard: heard)
        }
    }

    /// Whether the run closed up sounds like the entry read as one word; an all-capitals spelling is said letter by letter, so only its pronunciation is read.
    static func reads(_ entry: DictionaryEntry, as heard: String) -> Bool {
        let run = DoubleMetaphone.code(for: ReadingRestraint.closedUp(heard))
        guard !run.isSilent else { return false }
        let isLetters = entry.word.allSatisfy { $0.isUppercase || !$0.isLetter }
        let readings = isLetters ? [entry.pronunciation].compactMap { $0 } : [entry.word, entry.soundsLike]
        return readings.contains {
            run.sounds(like: DoubleMetaphone.code(for: ReadingRestraint.closedUp($0)))
        }
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

/// A dictionary entry as it would be written for one heard run, with any ending speech added to the name.
public struct DictionarySpelling: Sendable, Equatable {
    /// The entry the reading comes from.
    public let entry: DictionaryEntry
    /// The plural or possessive ending heard after the name, empty when the run is the name alone.
    public let ending: String
    /// The part of the heard run the entry stands for, without the ending.
    public let heard: String

    /// The entry's own spelling with the heard ending reattached, never respelt.
    public var word: String { entry.word + ending }
}

/// A run of consecutive doubted words; restated here rather than widening `UttrflowDictionary`'s own span.
struct UncertainSpan: Sendable, Equatable {
    /// Which words of the utterance the run covers.
    let range: Range<Int>
    /// The words with their spaces kept, which the phonetic index keys the same as the joined word.
    let text: String
    /// The lowest score the recogniser gave any word of the run, never a stand-in.
    let confidence: Double
    /// Why the run is doubted, which is kept apart from its score so neither has to stand in for the other.
    let reason: DoubtReason

    /// Every run up to the index's word limit in which every word is doubted, most deserving first.
    static func spans(in utterance: Utterance, below threshold: Double) -> [UncertainSpan] {
        spans(in: utterance.words.map { ($0.text, $0.confidence) }, below: threshold)
    }

    /// The same runs over a draft, reading the words as the passes left them and skipping what nobody said.
    static func spans(in draft: Draft, below threshold: Double) -> [UncertainSpan] {
        spans(in: saidWords(in: draft).map { ($0.text, $0.confidence) }, below: threshold)
    }

    /// The draft's words a run's range counts over: those still standing that the recogniser heard.
    static func saidWords(in draft: Draft) -> [Draft.Word] {
        draft.words.filter { $0.isPresent && !$0.isLayoutMark && !$0.heard.isEmpty }
    }

    /// Why one word is doubted, or `nil` when it is not: a low score first, else membership of a homophone group.
    private static func doubt(text: String, confidence: Double, below threshold: Double) -> DoubtReason? {
        if confidence < threshold { return .lowScore }
        return Homophones.group(containing: text) == nil ? nil : .homophoneClass
    }

    /// The runs themselves, over anything that can name a word and how sure the recogniser was of it.
    static func spans(
        in words: [(text: String, confidence: Double)], below threshold: Double
    ) -> [UncertainSpan] {
        let doubts = words.map { doubt(text: $0.text, confidence: $0.confidence, below: threshold) }
        var spans: [UncertainSpan] = []
        for start in words.indices {
            for length in 1...PhoneticIndex.maximumWordsPerEntry where start + length <= words.count {
                let range = start..<(start + length)
                guard doubts[range].allSatisfy({ $0 != nil }) else { break }
                spans.append(
                    UncertainSpan(
                        range: range,
                        text: words[range].map(\.text).joined(separator: " "),
                        confidence: words[range].reduce(1) { min($0, $1.confidence) },
                        reason: doubts[range].contains(.lowScore) ? .lowScore : .homophoneClass))
            }
        }
        return spans.sorted(by: isMoreDeserving)
    }

    /// A total order: a measured-low run before a class-only one, then least confident, earliest, longest.
    static func isMoreDeserving(_ first: UncertainSpan, _ second: UncertainSpan) -> Bool {
        if first.reason != second.reason { return first.reason < second.reason }
        if first.confidence != second.confidence { return first.confidence < second.confidence }
        if first.range.lowerBound != second.range.lowerBound {
            return first.range.lowerBound < second.range.lowerBound
        }
        return first.range.count > second.range.count
    }
}

/// Why a run of words is doubted, in the order the runs deserve another reading.
public enum DoubtReason: Int, Sendable, Comparable {
    /// The recogniser scored a word of the run below the certainty threshold.
    case lowScore
    /// Every word was heard surely, but one belongs to a homophone group whose partners sound the same.
    case homophoneClass

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
