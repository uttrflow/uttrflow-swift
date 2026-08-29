public import UttrflowCore
/// One named slice of a run, measured on its own.
///
/// The unit every breakdown is made of, and the reason there is a type for it: the
/// temptation at a thousand samples is to print one number, and one number over three
/// languages, twelve stresses and several speakers is an average of things that are not
/// alike. A slice always carries how much it rests on, so a 42% figure over eleven words
/// cannot be read as though it were a finding.
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

/// A recurring failure, and everywhere it happened.
///
/// The whole answer to "eighteen results can be a list; a thousand cannot". A run over a
/// thousand samples produces tens of thousands of individual word errors, and printing
/// them is the same as printing nothing. Nearly all of them are the same handful of
/// mistakes made over and over — one name the recogniser has never heard, one number
/// format, one loanword — so they are counted as one finding with a list of where it
/// bit, and ranked by how much they actually cost.
public struct Finding: Sendable, Equatable, Identifiable {
    /// What went wrong, reduced to something two samples can share.
    public enum Signature: Sendable, Equatable, Hashable, Codable {
        /// One word consistently heard as another. The single most actionable finding
        /// there is: it is usually one dictionary entry away from fixed.
        case misheard(String, heard: String)
        /// A reference word the transcript keeps dropping.
        case dropped(String)
        /// A word the recogniser keeps inventing.
        case inserted(String)
        /// A term the corpus insists on that keeps not surviving.
        case lostRequiredTerm(String)
        /// The recogniser answered in Devanagari, which the product cannot ship as it
        /// stands.
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
    /// How many times it happened in total. Larger than ``samples`` when one passage
    /// hits it more than once.
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
    /// Word error rate for one slice of the run, or `nil` when the slice is empty.
    ///
    /// Empty rather than zero, everywhere: a language nobody recorded has no rate, and
    /// printing 0% for it would read as perfection.
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

    /// One row per stress label the corpus actually used.
    ///
    /// Built from ``PassageScore/stresses``, so a sample stressing both proper nouns and
    /// a noisy room appears in both rows. **The rows therefore overlap and do not sum to
    /// the corpus** — which is the right trade: the question worth answering is "how are
    /// we on proper nouns", not "how are we on samples whose first label happens to be
    /// proper nouns". Every printer of this says so out loud.
    public var byStress: [ReportSlice] {
        let labels = Set(scored.flatMap(\.stresses)).sorted()
        return labels.compactMap { label in
            slice(label, of: scored.filter { $0.stresses.contains(label) })
        }
    }

    /// One row per recording cohort, with the unattributed recordings as their own row
    /// rather than folded in with anybody.
    public var byCohort: [ReportSlice] {
        let labels = Set(scored.map { $0.cohortID ?? RecordingCohort.unattributed }).sorted()
        return labels.compactMap { label in
            slice(label, of: scored.filter { ($0.cohortID ?? RecordingCohort.unattributed) == label })
        }
    }

    public func wordErrorRate(stressing label: String) -> WordErrorRate? {
        slice(label, of: scored.filter { $0.stresses.contains(label) })?.rate
    }

    /// Every recurring failure in the run, worst first.
    ///
    /// Ranked by occurrences and then by how many distinct samples hit it: a mistake made
    /// forty times across forty samples is a product problem, and the same mistake made
    /// forty times in one passage is that passage. Ties break on the description so the
    /// order does not move between runs over the same results.
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

    /// The findings worth printing, and how much was left out.
    ///
    /// A report that prints everything is a report nobody reads to the end, and a report
    /// that silently truncates is one nobody can trust. So the tail is counted and named.
    /// - Parameter limit: How many findings to show.
    /// - Returns: The top findings, and the number of occurrences in everything below them.
    public func topFindings(_ limit: Int) -> (shown: [Finding], hiddenOccurrences: Int, hidden: Int) {
        let all = findings
        guard all.count > limit else { return (all, 0, 0) }
        let hidden = all.dropFirst(limit)
        return (Array(all.prefix(limit)), hidden.reduce(0) { $0 + $1.occurrences }, hidden.count)
    }
}
