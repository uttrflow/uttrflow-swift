public import UttrflowCore

/// Why a passage produced no transcript to score.
///
/// Kept as three kinds rather than one, because they lead to different work: a
/// recogniser that heard nothing is a result, an engine that threw is a bug, and a file
/// the harness could not open is the harness's own fault and must not be charged to the
/// engine.
public enum TranscriptionFailure: Sendable, Equatable, Codable {
    /// The recording could not be read. The harness's problem, not the engine's.
    case audioUnreadable(String)
    /// The engine refused or threw.
    case engineFailed(String)
    /// The engine ran and returned nothing usable.
    case recognisedNothing

    public enum Kind: String, Sendable, Equatable, CaseIterable, Codable {
        case audioUnreadable
        case engineFailed
        case recognisedNothing
    }

    public var kind: Kind {
        switch self {
        case .audioUnreadable: .audioUnreadable
        case .engineFailed: .engineFailed
        case .recognisedNothing: .recognisedNothing
        }
    }

    public var detail: String {
        switch self {
        case .audioUnreadable(let description), .engineFailed(let description): description
        case .recognisedNothing: "the engine returned nothing"
        }
    }

    /// Whether the passage can still be scored.
    ///
    /// Hearing nothing is a transcript of no words, which is a perfectly measurable
    /// 100% deletion. An unreadable file is not a transcript at all, and scoring it
    /// would blame the engine for a missing recording.
    public var isScorable: Bool { kind != .audioUnreadable }
}

/// A stage timing as it is written to disk.
///
/// ``StageMeasurement`` is the type the whole product measures in and the one this
/// harness takes in; this is only its serialised form. `Duration` encodes as an opaque
/// pair of integers, and a results file that a person — or a one-line script — cannot
/// read is a results file nobody checks.
public struct StoredStageTiming: Sendable, Equatable, Codable {
    public let stage: PipelineStage
    public let seconds: Double
    public let succeeded: Bool

    public init(_ measurement: StageMeasurement) {
        stage = measurement.stage
        seconds = measurement.duration.inSeconds
        succeeded = measurement.succeeded
    }

    public var measurement: StageMeasurement {
        StageMeasurement(stage: stage, duration: .seconds(seconds), succeeded: succeeded)
    }
}

/// What one passage cost and how far off the transcript was.
public struct PassageScore: Sendable, Equatable, Codable, Identifiable {
    public var id: String { caseID }
    public let caseID: String
    public let language: TranscriptionCase.Language
    public let stressor: TranscriptionCase.Stressor
    /// Everything the passage stresses, in the corpus catalogue's vocabulary. Rows built
    /// from this overlap; see ``TranscriptionCase/stresses``.
    public let stresses: [String]
    /// Who read it and where. `nil` for a recording nobody attributed, which every
    /// report shows as its own row rather than merging into the rest.
    public let cohortID: String?
    /// `nil` only when there was no transcript to align against — see
    /// ``TranscriptionFailure/isScorable``.
    public let wordErrorRate: WordErrorRate?
    /// The script the engine answered in.
    ///
    /// `.devanagari` is itself a finding: Uttrflow's output is romanised Hinglish, so a
    /// recogniser answering in Devanagari has handed clean-up a transliteration job on
    /// top of everything else. The rate says how well it heard; the count of these says
    /// how much work it left behind.
    public let answeredIn: Script
    /// Which written form of the passage the transcript was compared with. Normally the
    /// one matching ``answeredIn``, because comparing across scripts measures
    /// transliteration rather than recognition.
    public let scoredAgainst: Script
    /// Terms the passage required that the transcript does not contain.
    public let lost: [String]
    /// What the engine actually said, kept so a bad score can be read rather than guessed at.
    public let transcript: String
    public let stages: [StoredStageTiming]
    public let failure: TranscriptionFailure?
    /// The rules both sides were put through. Stored per passage so a results file is
    /// self-describing: a rate without its normalisation is not a number anyone can act on.
    public let normalisation: [NormalisationRule]

    public init(
        caseID: String,
        language: TranscriptionCase.Language,
        stressor: TranscriptionCase.Stressor,
        wordErrorRate: WordErrorRate?,
        answeredIn: Script,
        scoredAgainst: Script,
        lost: [String] = [],
        transcript: String = "",
        stages: [StageMeasurement] = [],
        failure: TranscriptionFailure? = nil,
        normalisation: [NormalisationRule] = TextNormaliser.standard.rules,
        stresses: [String] = [],
        cohortID: String? = nil
    ) {
        self.caseID = caseID
        self.language = language
        self.stressor = stressor
        self.stresses = stresses.isEmpty ? [stressor.rawValue] : stresses
        self.cohortID = cohortID
        self.wordErrorRate = wordErrorRate
        self.answeredIn = answeredIn
        self.scoredAgainst = scoredAgainst
        self.lost = lost
        self.transcript = transcript
        self.stages = stages.map(StoredStageTiming.init)
        self.failure = failure
        self.normalisation = normalisation
    }

    /// Decoded by hand so that a results directory written before these two fields
    /// existed still summarises.
    ///
    /// `--summarise` reads what previous runs banked, and a synthesised decoder would
    /// refuse the lot the moment this type gained a field — turning every stored result
    /// into something that has to be measured again to be read.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        caseID = try container.decode(String.self, forKey: .caseID)
        language = try container.decode(TranscriptionCase.Language.self, forKey: .language)
        stressor = try container.decode(TranscriptionCase.Stressor.self, forKey: .stressor)
        stresses = try container.decodeIfPresent([String].self, forKey: .stresses) ?? [stressor.rawValue]
        cohortID = try container.decodeIfPresent(String.self, forKey: .cohortID)
        wordErrorRate = try container.decodeIfPresent(WordErrorRate.self, forKey: .wordErrorRate)
        answeredIn = try container.decode(Script.self, forKey: .answeredIn)
        scoredAgainst = try container.decode(Script.self, forKey: .scoredAgainst)
        lost = try container.decodeIfPresent([String].self, forKey: .lost) ?? []
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        stages = try container.decodeIfPresent([StoredStageTiming].self, forKey: .stages) ?? []
        failure = try container.decodeIfPresent(TranscriptionFailure.self, forKey: .failure)
        normalisation =
            try container.decodeIfPresent([NormalisationRule].self, forKey: .normalisation) ?? []
    }

    public var keptEverythingRequired: Bool { lost.isEmpty }

    /// The transcript had to be transliterated to be compared at all, so the rate is an
    /// upper bound: ICU romanises letter by letter and charges for spellings no person
    /// writes — "karana" where a Hinglish speaker types "karna".
    public var isUpperBound: Bool { answeredIn != scoredAgainst }
}

/// One stage's timings, summarised the way the diagnostics page summarises them.
///
/// Everything measured about one recogniser over the recorded corpus.
public struct TranscriptionReport: Sendable, Equatable {
    public let label: String
    public let scores: [PassageScore]

    public init(label: String, scores: [PassageScore]) {
        self.label = label
        self.scores = scores
    }

    /// Passages there was something to score.
    public var scored: [PassageScore] { scores.filter { $0.wordErrorRate != nil } }

    /// The headline: every error over every reference word, summed before dividing.
    public var overall: WordErrorRate { WordErrorRate.combined(scored.compactMap(\.wordErrorRate)) }

    public func wordErrorRate(in language: TranscriptionCase.Language) -> WordErrorRate? {
        combine(scored.filter { $0.language == language })
    }

    public func wordErrorRate(stressing stressor: TranscriptionCase.Stressor) -> WordErrorRate? {
        combine(scored.filter { $0.stressor == stressor })
    }

    private func combine(_ scores: [PassageScore]) -> WordErrorRate? {
        guard !scores.isEmpty else { return nil }
        return WordErrorRate.combined(scores.compactMap(\.wordErrorRate))
    }

    /// Failures by kind. A kind nobody hit is absent rather than zero, so the printer
    /// can say "none" once instead of listing three zeroes.
    public var failureCounts: [TranscriptionFailure.Kind: Int] {
        scores.compactMap { $0.failure?.kind }.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    /// Passages the recogniser answered in Devanagari, which the product cannot ship as
    /// it stands.
    public var answeredInDevanagari: [PassageScore] { scores.filter { $0.answeredIn == .devanagari } }

    /// Passages whose rate is an upper bound because the transcript had to be transliterated.
    public var upperBounds: [PassageScore] { scores.filter(\.isUpperBound) }

    public var passagesLosingRequiredTerms: [PassageScore] {
        scored.filter { !$0.keptEverythingRequired }
    }

    /// The rules every score was measured under, and whether they all agree.
    ///
    /// A store can end up holding passages measured under different rules — someone
    /// changed them and re-ran half the corpus — and a report that quietly printed one
    /// set of rules over a mixture would be exactly the untrustworthy number this type
    /// exists to prevent.
    public var normalisation: [NormalisationRule] { scores.first?.normalisation ?? [] }

    public var hasMixedNormalisation: Bool {
        !scores.allSatisfy { $0.normalisation == normalisation }
    }

    private var measurements: [StageMeasurement] { scores.flatMap(\.stages).map(\.measurement) }

    /// `nil` when nothing timed this stage. The caller must say "not measured" rather
    /// than printing a zero: this harness reads audio off disk, so capture is not timed
    /// here at all, and a zero would read as "instant".
    public func latency(for stage: PipelineStage) -> StageLatency? {
        StageLatency.summarise(measurements, stage: stage)
    }

    /// One entry per stage that was actually timed, in the order the journey runs.
    public var latencies: [StageLatency] { StageLatency.summarise(measurements) }

    /// Stages nothing measured, so the report can name them instead of implying they
    /// cost nothing.
    public var unmeasuredStages: [PipelineStage] {
        StageLatency.unmeasuredStages(in: measurements)
    }
}
