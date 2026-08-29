/// How well one rewrite matched what was wanted.
public struct CaseScore: Sendable, Equatable {
    public let caseID: String
    /// Word-level agreement with the reference, `0...1`.
    public let similarity: Double
    /// Whether every word that had to survive did.
    public let keptEverythingRequired: Bool
    /// Words that should have survived and did not.
    public let lost: [String]
    /// Words the rewrite invented that the case forbade. Worse than losing one: the
    /// user is shown something they never said.
    public let invented: [String]
    /// Whether the rewrite matched the reference exactly, ignoring case and spacing.
    public let isExact: Bool
    /// The engine said it could not handle this case at all.
    ///
    /// Kept apart from failure on purpose: an engine that correctly declines a
    /// language it does not know has behaved well, and scoring that as a wrong answer
    /// would make a principled refusal look like a mistake.
    public let declined: Bool

    public init(
        caseID: String, similarity: Double, keptEverythingRequired: Bool,
        lost: [String], isExact: Bool, declined: Bool = false, invented: [String] = []
    ) {
        self.caseID = caseID
        self.similarity = similarity
        self.keptEverythingRequired = keptEverythingRequired
        self.lost = lost
        self.isExact = isExact
        self.declined = declined
        self.invented = invented
    }

    /// A case passes only if it kept everything required *and* stayed close to the
    /// reference. Similarity alone would pass a rewrite that dropped someone's name.
    public var passed: Bool {
        !declined && keptEverythingRequired && invented.isEmpty && similarity >= 0.8
    }
}

/// Everything measured about one model across the corpus.
public struct EvaluationReport: Sendable, Equatable {
    public let label: String
    public let scores: [CaseScore]
    /// Wall-clock time per case, in the same order.
    public let durations: [Duration]
    /// Peak resident memory observed during the run, in bytes.
    public let peakMemoryBytes: Int64?

    public init(
        label: String, scores: [CaseScore], durations: [Duration], peakMemoryBytes: Int64? = nil
    ) {
        self.label = label
        self.scores = scores
        self.durations = durations
        self.peakMemoryBytes = peakMemoryBytes
    }

    /// Cases the engine actually attempted.
    public var attempted: [CaseScore] { scores.filter { !$0.declined } }

    /// How many cases the engine declined, most often for a language it does not know.
    public var declinedCount: Int { scores.count(where: \.declined) }

    /// Measured over what the engine attempted, so a refusal neither helps nor hurts
    /// its score — the declined count carries that story separately.
    public var passRate: Double {
        let attempted = attempted
        guard !attempted.isEmpty else { return 0 }
        return Double(attempted.count(where: \.passed)) / Double(attempted.count)
    }

    public var meanSimilarity: Double {
        let attempted = attempted
        guard !attempted.isEmpty else { return 0 }
        return attempted.map(\.similarity).reduce(0, +) / Double(attempted.count)
    }

    /// Cases that lost a word which had to survive. The most serious failure a
    /// dictation tool can have, so it is reported separately from the score.
    public var casesLosingRequiredWords: [CaseScore] {
        attempted.filter { !$0.keptEverythingRequired }
    }

    /// Cases where the engine added something the speaker never said.
    public var casesInventingWords: [CaseScore] {
        attempted.filter { !$0.invented.isEmpty }
    }

    /// The middle latency, which describes the usual wait better than a mean does.
    public var medianDuration: Duration {
        guard !durations.isEmpty else { return .zero }
        let sorted = durations.sorted()
        return sorted[sorted.count / 2]
    }

    public var slowestDuration: Duration {
        durations.max() ?? .zero
    }
}
