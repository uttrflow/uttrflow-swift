public import UttrflowCore
/// One named slice of a run, always carrying the word count it rests on.
public struct ReportSlice: Sendable, Equatable, Identifiable {
    public var id: String { label }
    public let label: String
    public let rate: WordErrorRate
    /// How many passages went into it.
    public let passages: Int

    public init(label: String, rate: WordErrorRate, passages: Int) {
        self.label = label
        self.rate = rate
        self.passages = passages
    }

    public var referenceWordCount: Int { rate.referenceWordCount }
}

/// A recurring failure and everywhere it happens, ranked by cost; the shape a thousand samples need.
public struct Finding: Sendable, Equatable, Identifiable {
    /// What went wrong, reduced to something two samples can share.
    public enum Signature: Sendable, Equatable, Hashable, Codable {
        /// One word consistently heard as another, usually one dictionary entry away from fixed.
        case misheard(String, heard: String)
        /// A reference word the transcript keeps dropping.
        case dropped(String)
        /// A word the recogniser keeps inventing.
        case inserted(String)
        /// A term the corpus insists on that keeps not surviving.
        case lostRequiredTerm(String)
        /// The recogniser answers in Devanagari, which the product cannot ship as it stands.
        case answeredInDevanagari
        /// The passage produced no transcript.
        case failed(TranscriptionFailure.Kind)

        public var description: String {
            switch self {
            case .misheard(let reference, let heard): "\"\(reference)\" heard as \"\(heard)\""
            case .dropped(let word): "\"\(word)\" dropped"
            case .inserted(let word): "\"\(word)\" invented"
            case .lostRequiredTerm(let term): "required term \"\(term)\" lost"
            case .answeredInDevanagari: "answered in Devanagari"
            case .failed(let kind): "failed: \(kind.rawValue)"
            }
        }
    }

    public var id: Signature { signature }
    public let signature: Signature
    /// How many times it happens in total; larger than ``samples`` when one passage hits it twice.
    public let occurrences: Int
    /// Which passages, in corpus order, so a finding can be looked into.
    public let samples: [String]

    public init(signature: Signature, occurrences: Int, samples: [String]) {
        self.signature = signature
        self.occurrences = occurrences
        self.samples = samples
    }

    public var sampleCount: Int { samples.count }
}

extension TranscriptionReport {
    /// Word error rate for one slice, or `nil` when the slice is empty, since 0% would read as perfection.
    private func slice(_ label: String, of scores: [PassageScore]) -> ReportSlice? {
        guard !scores.isEmpty else { return nil }
        return ReportSlice(
            label: label, rate: WordErrorRate.combined(scores.compactMap(\.wordErrorRate)),
            passages: scores.count)
    }

    /// One row per language, in a fixed order so two runs can be read side by side.
    public var byLanguage: [ReportSlice] {
        TranscriptionCase.Language.allCases.compactMap { language in
            slice(language.rawValue, of: scored.filter { $0.language == language })
        }
    }

    /// One row per stress label the corpus uses; rows overlap and do not sum to the corpus.
    public var byStress: [ReportSlice] {
        let labels = Set(scored.flatMap(\.stresses)).sorted()
        return labels.compactMap { label in
            slice(label, of: scored.filter { $0.stresses.contains(label) })
        }
    }

    /// One row per recording cohort, with unattributed recordings as their own row.
    public var byCohort: [ReportSlice] {
        let labels = Set(scored.map(\.cohortLabel)).sorted()
        return labels.compactMap { label in
            slice(label, of: scored.filter { $0.cohortLabel == label })
        }
    }

    public func wordErrorRate(stressing label: String) -> WordErrorRate? {
        slice(label, of: scored.filter { $0.stresses.contains(label) })?.rate
    }

    /// Every recurring failure, ranked by occurrences then distinct samples, with ties broken by text.
    public var findings: [Finding] {
        var occurrences: [Finding.Signature: Int] = [:]
        var samples: [Finding.Signature: [String]] = [:]

        func note(_ signature: Finding.Signature, in caseID: String) {
            occurrences[signature, default: 0] += 1
            if samples[signature]?.last != caseID { samples[signature, default: []].append(caseID) }
        }

        for score in scores {
            for operation in score.wordErrorRate?.alignment ?? [] {
                switch operation {
                case .match: continue
                case .substitution(let reference, let hypothesis):
                    note(.misheard(reference, heard: hypothesis), in: score.caseID)
                case .deletion(let word): note(.dropped(word), in: score.caseID)
                case .insertion(let word): note(.inserted(word), in: score.caseID)
                }
            }
            for term in score.lost { note(.lostRequiredTerm(term), in: score.caseID) }
            if score.answeredIn == .devanagari { note(.answeredInDevanagari, in: score.caseID) }
            if let failure = score.failure { note(.failed(failure.kind), in: score.caseID) }
        }

        return occurrences.map {
            Finding(signature: $0.key, occurrences: $0.value, samples: samples[$0.key] ?? [])
        }
        .sorted {
            ($1.occurrences, $1.sampleCount, $0.signature.description)
                < ($0.occurrences, $0.sampleCount, $1.signature.description)
        }
    }

    /// The top `limit` findings, and how many occurrences and findings are left out below them.
    public func topFindings(_ limit: Int) -> (shown: [Finding], hiddenOccurrences: Int, hidden: Int) {
        let all = findings
        guard all.count > limit else { return (all, 0, 0) }
        let hidden = all.dropFirst(limit)
        return (Array(all.prefix(limit)), hidden.reduce(0) { $0 + $1.occurrences }, hidden.count)
    }
}
