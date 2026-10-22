public import struct Foundation.UUID
private import NaturalLanguage
public import UttrflowCore
public import UttrflowDictionary

/// One other spelling of a doubtful run, and the dictionary entry it came from when it came from one.
public struct Reading: Sendable, Hashable, ExpressibleByStringLiteral {
    /// The words as they would be written.
    public let spelling: String
    /// The entry that taught this spelling, so a reading the model takes is counted like a correction; `nil` off the screen or the vocabulary.
    public let entryID: UUID?

    public init(_ spelling: String, entryID: UUID? = nil) {
        self.spelling = spelling
        self.entryID = entryID
    }

    /// A reading nobody taught, which is what a literal in a test or a fixture is.
    public init(stringLiteral spelling: String) {
        self.init(spelling)
    }
}

/// Where another reading of a doubtful word can come from. See `Docs/cleanup-design.md` §5.
public protocol CandidateSource: Sendable {
    /// The readings this source offers for one run of doubtful words, best first, in single-digit milliseconds.
    func candidates(for word: Draft.Word, in situation: Situation) async -> [Reading]

    /// The readings for every run of one piece, so what a source derives from the screen is derived once.
    func candidates(for words: [Draft.Word], in situation: Situation) async -> [[Reading]]

    /// Whether this source holds the word spelt as heard, so a sentence it looks out of place in cannot doubt it.
    func vouches(for heard: String, in situation: Situation) async -> Bool
}

/// A source of sound-alikes from the general vocabulary, which nobody wrote down, so no reading it offers is evidence in itself.
protocol SoundAlikeSource: CandidateSource {}

extension CandidateSource {
    /// One run at a time, which is right for a source whose index does not depend on the situation.
    public func candidates(for words: [Draft.Word], in situation: Situation) async -> [[Reading]] {
        var found: [[Reading]] = []
        for word in words { found.append(await candidates(for: word, in: situation)) }
        return found
    }

    /// A source of readings nobody wrote down holds no words of its own, so it vouches for none.
    public func vouches(for heard: String, in situation: Situation) async -> Bool { false }
}

/// A run of words the recogniser half-heard, and the readings the sources offered for it.
public struct DoubtfulSpan: Sendable, Equatable {
    /// The run as the model will read it, spaces and all, which is also what the guard looks for.
    public let heard: String
    /// The lowest score the recogniser gave the run, because a run is only as certain as its weakest word.
    public let confidence: Double
    /// Why the run is doubted, so a surely heard homophone is never printed as a low score.
    public let reason: DoubtReason
    /// The other readings, best first, each still carrying where it came from; a span with none is never offered to the model.
    public let candidates: [Reading]
    /// Which run closing up to `heard` was doubted, counted from 0, so a later mention of the same words is not offered its readings; `nil` names every such run.
    public let occurrence: Int?

    public init(
        heard: String, confidence: Double, reason: DoubtReason = .lowScore, candidates: [Reading],
        occurrence: Int? = nil
    ) {
        self.heard = heard
        self.confidence = confidence
        self.reason = reason
        self.candidates = candidates
        self.occurrence = occurrence
    }

    /// Whether the run at this place among the runs closing up to `heard` is the one that was doubted.
    func isDoubted(at place: Int) -> Bool { occurrence.map { $0 == place } ?? true }

    /// Every run of words closing up to this spelling, each counted once from the first word that carries a letter.
    static func runs(spelled spelling: String, in words: [String]) -> [Range<Int>] {
        guard !spelling.isEmpty else { return [] }
        var found: [Range<Int>] = []
        for start in words.indices where !closedUp(words[start]).isEmpty {
            var written = ""
            for end in start..<words.count {
                written += closedUp(words[end])
                guard written.count < spelling.count else {
                    if written == spelling { found.append(start..<(end + 1)) }
                    break
                }
            }
        }
        return found
    }

    /// Lower-cased letters and digits, so "payment sheet" and `PaymentSheet` read as the same spelling.
    static func closedUp(_ text: String) -> String { ReadingRestraint.closedUp(text) }
}

/// Asks every source at once what the words the recogniser was unsure of could have been.
public struct DoubtfulWords: Sendable {
    /// The most spans one piece may offer, so a bad recognition cannot grow the prompt without bound.
    public static let maximumSpans = WordCorrectionEngine.maximumChangedInEvery
    /// The most readings one span may offer, so a crowded sound cannot spend the whole line.
    public static let maximumCandidatesPerSpan = 3

    /// Asked in this order, and their answers merged in it, so the user's own words come before the screen's.
    public let sources: [any CandidateSource]
    /// Weighs each span's readings against each other before the span's limit is applied.
    public let scorer: any SpanScorer

    public init(sources: [any CandidateSource], scorer: any SpanScorer = SourceOrderScorer()) {
        self.sources = sources
        self.scorer = scorer
    }

    /// The sources that need nothing wired to them: the screen, the words everybody knows, shipped technical terms, and a homophone partner.
    public static let standard = DoubtfulWords(
        sources: [ScreenCandidates(), PhoneticCandidates(), TechnicalCandidates(), HomophoneCandidates()])

    /// The standard sources with the user's own dictionary asked first.
    public static func including(
        dictionary index: @escaping @Sendable () async -> PhoneticIndex
    ) -> DoubtfulWords {
        DoubtfulWords(sources: [DictionaryCandidates(index: index)] + standard.sources)
    }

    /// Every doubtful run that a source had a reading for, most deserving first and never overlapping.
    public func spans(in draft: Draft, for situation: Situation) async -> [DoubtfulSpan] {
        guard EvidencePolicy.unscored(draft, in: .doubtfulWords) == nil, !sources.isEmpty else { return [] }
        let said = UncertainSpan.saidWords(in: draft).map(\.text)
        let apart = await apartFromContext(in: draft, for: situation)
        let runs = UncertainSpan.spans(in: draft, apart: apart).filter {
            !Self.isCoordinator($0) && !Self.isCount($0, in: said)
        }
        guard !runs.isEmpty else { return [] }

        let reach = NGramModel.maxOrder - 1
        let words = runs.map { Draft.Word(text: $0.text, heard: $0.text, evidence: .score($0.confidence)) }
        let answers = await answers(for: words, in: situation)
        let offered = Self.hypotheses(
            for: words, answers: answers,
            around: runs.map { run in
                let lower = min(run.range.lowerBound, said.count)
                let upper = min(run.range.upperBound, said.count)
                return (
                    Array(said[max(lower - reach, 0)..<lower]),
                    Array(said[upper..<min(upper + reach, said.count)])
                )
            })
        var found: [DoubtfulSpan] = []
        var taken: [Range<Int>] = []
        for (place, (run, set)) in zip(runs, offered).enumerated()
        where !taken.contains(where: { $0.overlaps(run.range) }) {
            guard !set.hypotheses.isEmpty else { continue }
            let standing = Standing(
                evidenced: evidencedSpellings(answers, at: place),
                named: HeardWordFit.isName(run.range, in: said),
                ruledOut: HeardWordFit.ruledOut(run.range, in: said) != nil)
            let readings = set.ranked(by: scorer).filter {
                standing.admits($0) && Self.guardAccepts($0, for: run, in: draft)
            }
            guard !readings.isEmpty else { continue }
            taken.append(run.range)
            found.append(
                DoubtfulSpan(
                    heard: run.text, confidence: run.confidence, reason: run.reason,
                    candidates: Array(readings.prefix(Self.maximumCandidatesPerSpan)),
                    occurrence: DoubtfulSpan.runs(spelled: DoubtfulSpan.closedUp(run.text), in: said)
                        .firstIndex { $0.lowerBound == run.range.lowerBound }))
            if found.count == Self.maximumSpans { break }
        }
        return found
    }

    /// Whether the run is one coordinating conjunction, which joins two alternatives or additions, so a sound-alike in its place always changes what was said.
    private static func isCoordinator(_ run: UncertainSpan) -> Bool {
        run.range.count == 1 && FunctionWords.isCoordinator(run.text)
    }

    /// Whether the run is one number word its sentence reads as a count, before what it counts ("two designers") or after a determiner ("the one I"), so a sound-alike in its place changes the number said.
    private static func isCount(_ run: UncertainSpan, in said: [String]) -> Bool {
        let index = run.range.lowerBound
        guard run.range.count == 1, NumberWords.value(of: WordShape(run.text).key) != nil,
            LexicalClass.tag(ofWordAt: index, in: said) == .number
        else { return false }
        let next = LexicalClass.tag(ofWordAt: index + 1, in: said)
        let counted = next == .noun || next == .adjective
        let determined = index > 0 && FunctionWords.determiners.contains(WordShape(said[index - 1]).key)
        return counted || determined
    }

    /// The spellings a source other than a `SoundAlikeSource` offered for the run at `place`, lower-cased.
    private func evidencedSpellings(_ answers: [[[Reading]]], at place: Int) -> Set<String> {
        Set(
            sources.indices.filter { !(sources[$0] is any SoundAlikeSource) }
                .flatMap { answers[$0][place] }.map { $0.spelling.lowercased() })
    }

    /// What stands behind the heard run, which decides whether a reading may replace it. See Docs/cleanup.md.
    struct Standing {
        /// The spellings an evidence source offered, lower-cased.
        let evidenced: Set<String>
        /// Whether the run holds a name, which only the user's dictionary may re-spell.
        let named: Bool
        /// Whether a `HeardWordFit` rule says the heard words cannot stand where they were said.
        let ruledOut: Bool

        /// Whether the reading may be offered: the user's dictionary holds it, or the run is no name and an evidence source offered the reading or the heard words cannot stand.
        func admits(_ reading: Reading) -> Bool {
            if reading.entryID != nil { return true }
            return !named && (ruledOut || evidenced.contains(reading.spelling.lowercased()))
        }
    }

    /// The said words context doubts, less any the user's dictionary, the screen or the shipped terms hold as heard.
    private func apartFromContext(in draft: Draft, for situation: Situation) async -> Set<Int> {
        let said = UncertainSpan.saidWords(in: draft)
        var apart: Set<Int> = []
        for index in ContextDoubt.doubted(said.map { ($0.text, $0.confidence, $0.settled) }) {
            var held = false
            for source in sources where !held {
                held = await source.vouches(for: said[index].text, in: situation)
            }
            if !held { apart.insert(index) }
        }
        return apart
    }

    /// Whether the guard, the one judge of a swap, accepts this reading written over the run alone. See Docs/cleanup.md.
    static func guardAccepts(_ reading: Reading, for run: UncertainSpan, in draft: Draft) -> Bool {
        let said = draft.words.indices.filter {
            draft.words[$0].isPresent && !draft.words[$0].isLayoutMark && !draft.words[$0].heard.isEmpty
        }
        guard run.range.upperBound <= said.count else { return false }
        var swapped = draft
        for position in run.range.dropFirst().reversed() {
            swapped.remove(at: said[position], by: "doubtfulWords")
        }
        swapped.replace(at: said[run.range.lowerBound], with: reading.spelling, by: "doubtfulWords")
        let alone = DoubtfulSpan(
            heard: run.text, confidence: run.confidence, reason: run.reason, candidates: [reading],
            occurrence: DoubtfulSpan.runs(
                spelled: DoubtfulSpan.closedUp(run.text), in: said.map { draft.words[$0].text }
            )
            .firstIndex { $0.lowerBound == run.range.lowerBound })
        return MeaningPreservationGuard().verdict(draft: draft, rewritten: swapped.text, offering: [alone])
            .isAccepted
    }

    /// Every source's answer for every run, with the said words `around` it when given, the sources running beside each other because they share nothing.
    public func hypotheses(
        for words: [Draft.Word], around context: [(before: [String], after: [String])] = [],
        in situation: Situation
    ) async -> [HypothesisSet] {
        Self.hypotheses(for: words, answers: await answers(for: words, in: situation), around: context)
    }

    /// Every source's readings for every run, by source then run, the sources running beside each other.
    private func answers(for words: [Draft.Word], in situation: Situation) async -> [[[Reading]]] {
        var answers: [[[Reading]]] = Array(repeating: [], count: sources.count)
        await withTaskGroup(of: (Int, [[Reading]]).self) { group in
            for (position, source) in sources.enumerated() {
                group.addTask { (position, await source.candidates(for: words, in: situation)) }
            }
            for await (position, found) in group { answers[position] = found }
        }
        return answers
    }

    /// The sources' answers gathered per run, with the said words `around` each run when given.
    private static func hypotheses(
        for words: [Draft.Word], answers: [[[Reading]]], around context: [(before: [String], after: [String])]
    ) -> [HypothesisSet] {
        words.indices.map { index -> HypothesisSet in
            let near: (before: [String], after: [String]) =
                context.indices.contains(index) ? context[index] : ([], [])
            return HypothesisSet(
                heard: words[index].text, confidence: words[index].confidence,
                answers: answers.map { $0[index] }, before: near.before, after: near.after)
        }
    }

    /// The sources' readings in the order they were asked, each once, and never the words as they were heard.
    static func merged(_ answers: [[Reading]], heard: String) -> [Reading] {
        HypothesisSet(heard: heard, confidence: 0, answers: answers).hypotheses.map(\.reading)
    }
}
