public import UttrflowCore
public import UttrflowDictionary

/// Where another reading of a doubtful word can come from. See `Docs/cleanup-design.md` §5.
public protocol CandidateSource: Sendable {
    /// The readings this source offers for one run of doubtful words, best first, in single-digit milliseconds.
    func candidates(for word: Draft.Word, in situation: Situation) async -> [String]
}

/// A run of words the recogniser half-heard, and the readings the sources offered for it.
public struct DoubtfulSpan: Sendable, Equatable {
    /// The run as the model will read it, spaces and all, which is also what the guard looks for.
    public let heard: String
    /// The lowest confidence in the run, because a run is only as certain as its weakest word.
    public let confidence: Double
    /// The other readings, best first; a span with none is never offered to the model.
    public let candidates: [String]

    public init(heard: String, confidence: Double, candidates: [String]) {
        self.heard = heard
        self.confidence = confidence
        self.candidates = candidates
    }

    /// Lower-cased letters and digits, so "payment sheet" and `PaymentSheet` read as the same spelling.
    static func closedUp(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// Asks every source at once what the words the recogniser was unsure of could have been.
public struct DoubtfulWords: Sendable {
    /// The most spans one piece may offer, so a bad recognition cannot grow the prompt without bound.
    public static let maximumSpans = WordCorrectionEngine.maximumChangedInEvery
    /// The most readings one span may offer, so a crowded sound cannot spend the whole line.
    public static let maximumCandidatesPerSpan = 3

    /// Asked in this order, and their answers merged in it, so the user's own words come before the screen's.
    public let sources: [any CandidateSource]

    public init(sources: [any CandidateSource]) {
        self.sources = sources
    }

    /// The two sources that need nothing wired to them: the screen, and the words everybody knows.
    public static let standard = DoubtfulWords(sources: [ScreenCandidates(), PhoneticCandidates()])

    /// The standard sources with the user's own dictionary asked first.
    public static func including(
        dictionary index: @escaping @Sendable () async -> PhoneticIndex
    ) -> DoubtfulWords {
        DoubtfulWords(sources: [DictionaryCandidates(index: index)] + standard.sources)
    }

    /// Every doubtful run that a source had a reading for, most deserving first and never overlapping.
    public func spans(in draft: Draft, for situation: Situation) async -> [DoubtfulSpan] {
        // A draft whose confidences are a stand-in reads as certain throughout, so the feature must not fire.
        guard draft.confidencesAreReal, !sources.isEmpty else { return [] }
        let runs = UncertainSpan.spans(in: draft, below: WordCorrectionEngine.certaintyThreshold)
        guard !runs.isEmpty else { return [] }

        let offered = await readings(
            for: runs.map { Draft.Word(text: $0.text, heard: $0.text, confidence: $0.confidence) },
            in: situation)
        var found: [DoubtfulSpan] = []
        var taken: [Range<Int>] = []
        for (run, readings) in zip(runs, offered)
        where !readings.isEmpty && !taken.contains(where: { $0.overlaps(run.range) }) {
            taken.append(run.range)
            found.append(
                DoubtfulSpan(
                    heard: run.text, confidence: run.confidence,
                    candidates: Array(readings.prefix(Self.maximumCandidatesPerSpan))))
            if found.count == Self.maximumSpans { break }
        }
        return found
    }

    /// Every source's answer for every run, the sources running beside each other because they share nothing.
    private func readings(for words: [Draft.Word], in situation: Situation) async -> [[String]] {
        var answers: [[[String]]] = Array(repeating: [], count: sources.count)
        await withTaskGroup(of: (Int, [[String]]).self) { group in
            for (position, source) in sources.enumerated() {
                group.addTask {
                    var found: [[String]] = []
                    for word in words { found.append(await source.candidates(for: word, in: situation)) }
                    return (position, found)
                }
            }
            for await (position, found) in group { answers[position] = found }
        }
        return words.indices.map { index in Self.merged(answers.map { $0[index] }, heard: words[index].text) }
    }

    /// The sources' readings in the order they were asked, each once, and never the words as they were heard.
    static func merged(_ answers: [[String]], heard: String) -> [String] {
        var seen: Set<String> = []
        return answers.flatMap { $0 }
            .filter { $0 != heard && !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
