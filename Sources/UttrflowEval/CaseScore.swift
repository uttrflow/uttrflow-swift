// One clean-up case's score and the report built from many.

/// How well one rewrite matched what was wanted.
public struct CaseScore: Sendable, Equatable {
    public let caseID: String
    /// Word-level agreement with the reference, `0...1`.
    public let similarity: Double
    /// The mean per-mark F1 of `marks`.
    public let markAccuracy: Double
    /// Agreement on the case of words shared with the reference.
    public let caseAccuracy: Double
    /// Whether every word that had to survive did.
    public let keptEverythingRequired: Bool
    /// Words that should have survived and did not.
    public let lost: [String]
    /// Reference words the rewrite dropped with nothing in their place, in reference order.
    public let deleted: [String]
    /// Words the rewrite invented that the case forbids; worse than losing one.
    public let invented: [String]
    /// Each required beginning or ending the rewrite did not have, named by its side.
    public let brokeShape: [String]
    /// Whether the rewrite matched the reference exactly after whitespace is collapsed.
    public let isExact: Bool
    /// Whether the engine declined the case; kept apart from failure so a refusal is not a mistake.
    public let declined: Bool
    /// Case agreement counted per capitalisation class; `caseAccuracy` is its total.
    public let capitalisation: CapitalisationTally
    /// Punctuation agreement counted per mark over aligned words; `markAccuracy` is its mean.
    public let marks: PunctuationTally
    /// The same count for the reference written all lower case, the do-nothing floor.
    public let lowerCaseBaseline: CapitalisationTally
    /// The same count for the recogniser's own text, before any clean-up.
    public let spokenBaseline: CapitalisationTally

    public init(
        caseID: String, similarity: Double, markAccuracy: Double = 1, caseAccuracy: Double = 1,
        keptEverythingRequired: Bool,
        lost: [String], isExact: Bool, declined: Bool = false, invented: [String] = [],
        brokeShape: [String] = [], deleted: [String] = [],
        capitalisation: CapitalisationTally = .init(), marks: PunctuationTally = .init(),
        lowerCaseBaseline: CapitalisationTally = .init(),
        spokenBaseline: CapitalisationTally = .init()
    ) {
        self.caseID = caseID
        self.similarity = similarity
        self.markAccuracy = markAccuracy
        self.caseAccuracy = caseAccuracy
        self.keptEverythingRequired = keptEverythingRequired
        self.lost = lost
        self.isExact = isExact
        self.declined = declined
        self.invented = invented
        self.brokeShape = brokeShape
        self.deleted = deleted
        self.capitalisation = capitalisation
        self.marks = marks
        self.lowerCaseBaseline = lowerCaseBaseline
        self.spokenBaseline = spokenBaseline
    }

    /// Passes only when no reference word is dropped, nothing required is lost and the rewrite stays close.
    public var passed: Bool {
        !declined && keptEverythingRequired && deleted.isEmpty && invented.isEmpty && brokeShape.isEmpty
            && similarity >= 0.8
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

    /// Pass rate over what the engine attempted, so a refusal neither helps nor hurts.
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

    public var meanMarkAccuracy: Double {
        mean(of: \CaseScore.markAccuracy)
    }

    public var meanCaseAccuracy: Double {
        mean(of: \CaseScore.caseAccuracy)
    }

    /// Case agreement per class summed over attempted cases, so a class is weighed by its words.
    public var capitalisation: CapitalisationTally { attempted.map(\.capitalisation).reduce(.init(), +) }

    /// Punctuation agreement per mark summed over attempted cases, so a mark is weighed by its count.
    public var marks: PunctuationTally { attempted.map(\.marks).reduce(.init(), +) }

    /// The all-lower-case floor summed the same way.
    public var lowerCaseBaseline: CapitalisationTally {
        attempted.map(\.lowerCaseBaseline).reduce(.init(), +)
    }

    /// The recogniser's own case summed the same way.
    public var spokenBaseline: CapitalisationTally { attempted.map(\.spokenBaseline).reduce(.init(), +) }

    private func mean(of metric: (CaseScore) -> Double) -> Double {
        let attempted = attempted
        guard !attempted.isEmpty else { return 0 }
        return attempted.map(metric).reduce(0, +) / Double(attempted.count)
    }

    /// Cases that lost a word which had to survive, the most serious failure a dictation tool has.
    public var casesLosingRequiredWords: [CaseScore] {
        attempted.filter { !$0.keptEverythingRequired }
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
