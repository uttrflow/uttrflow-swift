// A stored accuracy run and the gate that compares later runs against it.
public import Foundation

/// One sample's errors and reference words, kept as counts so any slice can be recomputed exactly.
public struct BaselineEntry: Sendable, Equatable, Codable, Identifiable {
    public var id: String { caseID }
    public let caseID: String
    public let language: TranscriptionCase.Language
    public let stresses: [String]
    public let cohortID: String?
    public let errors: Int
    public let referenceWordCount: Int
    /// Whether the passage produced nothing to score; counted separately from the rates.
    public let isUnscorable: Bool
    /// The exact audio scored; `nil` for an entry captured before this was tracked.
    public let recordingIdentity: String?

    public init(
        caseID: String,
        language: TranscriptionCase.Language,
        stresses: [String],
        cohortID: String?,
        errors: Int,
        referenceWordCount: Int,
        isUnscorable: Bool,
        recordingIdentity: String? = nil
    ) {
        self.caseID = caseID
        self.language = language
        self.stresses = stresses
        self.cohortID = cohortID
        self.errors = errors
        self.referenceWordCount = referenceWordCount
        self.isUnscorable = isUnscorable
        self.recordingIdentity = recordingIdentity
    }

    public init(_ score: PassageScore) {
        self.init(
            caseID: score.caseID,
            language: score.language,
            stresses: score.stresses,
            cohortID: score.cohortID,
            errors: score.wordErrorRate?.errors ?? 0,
            referenceWordCount: score.wordErrorRate?.referenceWordCount ?? 0,
            isUnscorable: score.wordErrorRate == nil,
            recordingIdentity: score.recordingIdentity
        )
    }

    public var rate: Double? {
        guard referenceWordCount > 0 else { return nil }
        return Double(errors) / Double(referenceWordCount)
    }

    /// The cohort to report under, naming the unattributed rather than merging them.
    var cohortLabel: String { cohortID ?? RecordingCohort.unattributed }
}

/// A stored accuracy run that later runs are gated against. See Docs/eval-methodology.md.
public struct AccuracyBaseline: Sendable, Equatable, Codable, Identifiable {
    public var id: String { label }
    /// What was measured: engine, model, hinting; baselines with different labels are never compared.
    public let label: String
    /// The recogniser pins the rates were measured with; `nil` for a baseline saved before they were recorded.
    public let recogniser: String?
    public let recordedAt: Date
    /// The rules the rates were measured under; a comparison across different rules is refused.
    public let normalisation: [NormalisationRule]
    public let entries: [BaselineEntry]

    public init(
        label: String, recogniser: String? = nil, recordedAt: Date, normalisation: [NormalisationRule],
        entries: [BaselineEntry]
    ) {
        self.label = label
        self.recogniser = recogniser
        self.recordedAt = recordedAt
        self.normalisation = normalisation
        // Sorted so two baselines over the same corpus are byte-identical, diffable files.
        self.entries = entries.sorted { $0.caseID < $1.caseID }
    }

    public static func capture(_ report: TranscriptionReport, at moment: Date = Date()) -> AccuracyBaseline {
        AccuracyBaseline(
            label: report.label, recogniser: report.recogniser, recordedAt: moment,
            normalisation: report.normalisation,
            entries: report.scores.map(BaselineEntry.init))
    }

    // MARK: On disk

    /// The file name under the repository, where a baseline can be committed and gate other people's changes.
    public static let defaultFileName = "accuracy-baseline.json"

    public func write(to url: URL) throws(EvaluationStoreError) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .readable
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(self).write(to: url, options: .atomic)
        } catch {
            throw .couldNotWrite(path: url.lastPathComponent, reason: "\(error)")
        }
    }

    public static func read(from url: URL) throws(EvaluationStoreError) -> AccuracyBaseline {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AccuracyBaseline.self, from: try Data(contentsOf: url))
        } catch {
            throw .couldNotRead(path: url.lastPathComponent, reason: "\(error)")
        }
    }
}

/// Whether a change made things better or worse, said one slice at a time.
public struct BaselineComparison: Sendable, Equatable {
    public enum Verdict: String, Sendable, Equatable {
        case improved
        case worsened
        /// The interval holds zero: the sample cannot tell this run from the baseline.
        case unchanged = "no change detectable"
        /// The two runs do not describe the same thing, so no verdict is honest.
        case incomparable
    }

    /// One slice, before and after.
    public struct Change: Sendable, Equatable, Identifiable {
        public var id: String { label }
        public let label: String
        public let before: Double?
        public let after: Double?
        /// How many reference words the slice rests on now, reported beside every delta.
        public let referenceWordCount: Int
        public let verdict: Verdict
        /// The confidence interval for the change in rate; `nil` when the slice has too few utterances.
        public let interval: ClosedRange<Double>?
        /// The smallest change in rate this slice can resolve; `nil` when there is no interval.
        public let minimumDetectableChange: Double?
        /// Whether the slice has too few utterances for an interval, so it is reported and never ruled on.
        public let isUnderpowered: Bool

        public init(
            label: String,
            before: Double?,
            after: Double?,
            referenceWordCount: Int,
            verdict: Verdict,
            interval: ClosedRange<Double>? = nil,
            minimumDetectableChange: Double? = nil
        ) {
            self.label = label
            self.before = before
            self.after = after
            self.referenceWordCount = referenceWordCount
            self.verdict = verdict
            self.interval = interval
            self.minimumDetectableChange = minimumDetectableChange
            self.isUnderpowered = interval == nil
        }

        public var delta: Double? {
            guard let before, let after else { return nil }
            return after - before
        }
    }

    public let baselineLabel: String
    public let overall: Change
    public let byLanguage: [Change]
    public let byStress: [Change]
    public let byCohort: [Change]
    /// Samples measured in both runs whose own rate got worse, worst first.
    public let regressed: [Change]
    public let improved: [Change]
    /// Samples the baseline never saw; every figure above is computed over the shared samples only.
    public let added: [String]
    public let removed: [String]
    /// Samples that produce nothing to score in the new run but did in the baseline.
    public let newlyUnscorable: [String]
    public let reason: String?

    public var verdict: Verdict {
        if reason != nil { return .incomparable }
        // Any judged slice going backwards is a regression, even when the headline improved.
        let slices = [overall] + byLanguage + byStress + byCohort
        if slices.contains(where: { $0.verdict == .worsened }) { return .worsened }
        if !newlyUnscorable.isEmpty { return .worsened }
        if overall.verdict == .improved { return .improved }
        return .unchanged
    }

    /// Whether a slice got worse. An incomparable comparison is not a regression; see `failsGate`.
    public var isRegression: Bool { verdict == .worsened }

    /// Whether a gate should refuse to pass: a regression, or a comparison with no verdict, which must not count as a pass.
    public var failsGate: Bool { verdict == .worsened || verdict == .incomparable }
}

extension AccuracyBaseline {
    /// Compares a fresh run with this baseline over the samples they share, reporting the rest.
    public func compare(with report: TranscriptionReport) -> BaselineComparison {
        compare(with: report, method: .standard)
    }

    /// The same comparison under another bootstrap configuration.
    func compare(with report: TranscriptionReport, method: PairedBootstrap) -> BaselineComparison {
        compare(
            with: AccuracyBaseline(
                label: report.label, recogniser: report.recogniser, recordedAt: recordedAt,
                normalisation: report.normalisation, entries: report.scores.map(BaselineEntry.init)),
            method: method)
    }

    /// Compares a later baseline with this one, as a release report does with the release before it.
    func compare(with later: AccuracyBaseline, method: PairedBootstrap = .standard) -> BaselineComparison {
        let after = Dictionary(later.entries.map { ($0.caseID, $0) }) { first, _ in first }
        let before = Dictionary(entries.map { ($0.caseID, $0) }) { first, _ in first }
        let shared = Set(before.keys).intersection(after.keys).sorted()

        let mismatch = incomparability(with: later, shared: shared, before: before, after: after)
        let sharedBefore = shared.compactMap { before[$0] }
        let sharedAfter = shared.compactMap { after[$0] }

        return BaselineComparison(
            baselineLabel: label,
            overall: change("overall", sharedBefore, sharedAfter, method),
            byLanguage: TranscriptionCase.Language.allCases.compactMap { language in
                slice(language.rawValue, sharedBefore, sharedAfter, method) { $0.language == language }
            },
            byStress: Set(sharedBefore.flatMap(\.stresses)).sorted().compactMap { label in
                slice(label, sharedBefore, sharedAfter, method) { $0.stresses.contains(label) }
            },
            byCohort: Set(sharedBefore.map(\.cohortLabel)).sorted().compactMap { label in
                slice(label, sharedBefore, sharedAfter, method) { $0.cohortLabel == label }
            },
            regressed: movedSamples(shared, before, after, worse: true),
            improved: movedSamples(shared, before, after, worse: false),
            added: after.keys.filter { before[$0] == nil }.sorted(),
            removed: before.keys.filter { after[$0] == nil }.sorted(),
            newlyUnscorable: shared.filter {
                after[$0]?.isUnscorable == true && before[$0]?.isUnscorable == false
            },
            reason: mismatch
        )
    }

    /// Why these two runs are not about the same thing, if they are not; growth is not a reason.
    private func incomparability(
        with report: AccuracyBaseline, shared: [String],
        before: [String: BaselineEntry], after: [String: BaselineEntry]
    ) -> String? {
        if report.label != label {
            return "the baseline measured \(label) and this run measured \(report.label), "
                + "so the rates are not comparable"
        }
        if let mismatch = recogniserMismatch(report.recogniser) { return mismatch }
        if shared.isEmpty {
            return "the baseline and this run share no samples"
        }
        if report.normalisation != normalisation {
            if normalisation.isEmpty {
                return "the baseline's normalisation rules are not recorded (a legacy baseline) "
                    + "— re-measure the baseline so the new rules are saved alongside it"
            }
            if report.normalisation.isEmpty {
                return "the run's normalisation rules are not recorded (a legacy result file) "
                    + "— re-measure the run so the rules are saved alongside the scores"
            }
            return "the normalisation rules changed since the baseline, so the rates are not comparable "
                + "— re-measure the baseline so the new rules are saved alongside it"
        }
        let (mismatched, unverifiable) = audioIdentityIssues(shared, before, after)
        if !mismatched.isEmpty {
            return "the recording changed since the baseline for "
                + mismatched.joined(separator: ", ") + ", so the movement there is not the engine's"
        }
        if !unverifiable.isEmpty {
            return "no recording identity to check " + unverifiable.joined(separator: ", ")
                + " against the baseline, so a replacement recording cannot be ruled out"
        }
        return nil
    }

    /// Why the recogniser pins differ, if they do; a new baseline saved in the same change clears it.
    private func recogniserMismatch(_ measured: String?) -> String? {
        guard measured != recogniser else { return nil }
        guard let recogniser else {
            return "the baseline does not record which model it is for — save a new baseline"
        }
        return "baseline is for a different model (\(recogniser), this run \(measured ?? "unrecorded")) "
            + "— save a new baseline in the same change"
    }

    /// Where a shared case ID's audio provably changed, and where it cannot be checked either way.
    private func audioIdentityIssues(
        _ shared: [String], _ before: [String: BaselineEntry], _ after: [String: BaselineEntry]
    ) -> (mismatched: [String], unverifiable: [String]) {
        var mismatched: [String] = []
        var unverifiable: [String] = []
        for caseID in shared {
            switch (before[caseID]?.recordingIdentity, after[caseID]?.recordingIdentity) {
            case (let some?, let other?):
                if some != other { mismatched.append(caseID) }
            case (nil, nil):
                // Neither side ever tracked identity; no signal either way, so the pair is left alone.
                break
            default:
                // One side tracked identity and the other did not — a legacy baseline meeting a fresh run.
                unverifiable.append(caseID)
            }
        }
        return (mismatched.sorted(), unverifiable.sorted())
    }

    private func change(
        _ label: String, _ before: [BaselineEntry], _ after: [BaselineEntry],
        _ method: PairedBootstrap
    ) -> BaselineComparison.Change {
        let afterByID = Dictionary(after.map { ($0.caseID, $0) }) { first, _ in first }
        let pairs = before.compactMap { was -> PairedBootstrap.Pair? in
            guard let now = afterByID[was.caseID], !was.isUnscorable, !now.isUnscorable else { return nil }
            return PairedBootstrap.Pair(
                errorsBefore: was.errors, wordsBefore: was.referenceWordCount,
                errorsAfter: now.errors, wordsAfter: now.referenceWordCount)
        }
        let estimate = method.estimate(pairs)
        let verdict: BaselineComparison.Verdict =
            switch estimate?.interval {
            case let interval? where interval.lowerBound > 0: .worsened
            case let interval? where interval.upperBound < 0: .improved
            default: .unchanged
            }
        return BaselineComparison.Change(
            label: label, before: rate(of: before), after: rate(of: after),
            referenceWordCount: after.reduce(0) { $0 + $1.referenceWordCount },
            verdict: verdict, interval: estimate?.interval,
            minimumDetectableChange: estimate?.minimumDetectableChange)
    }

    private func slice(
        _ label: String, _ before: [BaselineEntry], _ after: [BaselineEntry],
        _ method: PairedBootstrap, matching: (BaselineEntry) -> Bool
    ) -> BaselineComparison.Change? {
        let matchedBefore = before.filter(matching)
        guard !matchedBefore.isEmpty else { return nil }
        return change(label, matchedBefore, after.filter(matching), method)
    }

    /// Individual samples whose own rate moved, as evidence for a slice's verdict, never a verdict.
    private func movedSamples(
        _ shared: [String], _ before: [String: BaselineEntry], _ after: [String: BaselineEntry], worse: Bool
    ) -> [BaselineComparison.Change] {
        shared.compactMap { caseID -> BaselineComparison.Change? in
            guard let was = before[caseID]?.rate, let now = after[caseID]?.rate else { return nil }
            guard worse ? now > was : now < was else { return nil }
            return BaselineComparison.Change(
                label: caseID, before: was, after: now,
                referenceWordCount: after[caseID]?.referenceWordCount ?? 0,
                verdict: worse ? .worsened : .improved)
        }
        .sorted { abs($0.delta ?? 0) > abs($1.delta ?? 0) }
    }

    private func rate(of entries: [BaselineEntry]) -> Double? {
        let words = entries.reduce(0) { $0 + $1.referenceWordCount }
        guard words > 0 else { return nil }
        return Double(entries.reduce(0) { $0 + $1.errors }) / Double(words)
    }
}
