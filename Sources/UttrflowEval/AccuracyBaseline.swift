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

    public init(
        caseID: String,
        language: TranscriptionCase.Language,
        stresses: [String],
        cohortID: String?,
        errors: Int,
        referenceWordCount: Int,
        isUnscorable: Bool
    ) {
        self.caseID = caseID
        self.language = language
        self.stresses = stresses
        self.cohortID = cohortID
        self.errors = errors
        self.referenceWordCount = referenceWordCount
        self.isUnscorable = isUnscorable
    }

    public init(_ score: PassageScore) {
        self.init(
            caseID: score.caseID,
            language: score.language,
            stresses: score.stresses,
            cohortID: score.cohortID,
            errors: score.wordErrorRate?.errors ?? 0,
            referenceWordCount: score.wordErrorRate?.referenceWordCount ?? 0,
            isUnscorable: score.wordErrorRate == nil
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
    public let recordedAt: Date
    /// The rules the rates were measured under; a comparison across different rules is refused.
    public let normalisation: [NormalisationRule]
    public let entries: [BaselineEntry]

    public init(
        label: String, recordedAt: Date, normalisation: [NormalisationRule], entries: [BaselineEntry]
    ) {
        self.label = label
        self.recordedAt = recordedAt
        self.normalisation = normalisation
        // Sorted so two baselines over the same corpus are byte-identical, diffable files.
        self.entries = entries.sorted { $0.caseID < $1.caseID }
    }

    public static func capture(_ report: TranscriptionReport, at moment: Date = Date()) -> AccuracyBaseline {
        AccuracyBaseline(
            label: report.label, recordedAt: moment, normalisation: report.normalisation,
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

/// How much movement counts as movement, so the gate does not fire on run-to-run noise.
public struct RegressionTolerance: Sendable, Equatable {
    /// How far a rate may move before it is a finding, in percentage points.
    public let percentagePoints: Double
    /// Reference words a slice needs before it is judged; smaller slices report as "too small to judge".
    public let minimumReferenceWords: Int

    public init(percentagePoints: Double = 0.5, minimumReferenceWords: Int = 200) {
        self.percentagePoints = percentagePoints
        self.minimumReferenceWords = minimumReferenceWords
    }

    public static let standard = RegressionTolerance()
}

/// Whether a change made things better or worse, said one slice at a time.
public struct BaselineComparison: Sendable, Equatable {
    public enum Verdict: String, Sendable, Equatable {
        case improved
        case worsened
        case unchanged
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
        /// Whether the slice is too small to judge, making its verdict ``Verdict/unchanged`` by default.
        public let isUnderpowered: Bool

        public init(
            label: String,
            before: Double?,
            after: Double?,
            referenceWordCount: Int,
            verdict: Verdict,
            isUnderpowered: Bool = false
        ) {
            self.label = label
            self.before = before
            self.after = after
            self.referenceWordCount = referenceWordCount
            self.verdict = verdict
            self.isUnderpowered = isUnderpowered
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

    /// Whether a build should stop here.
    public var isRegression: Bool { verdict == .worsened }
}

extension AccuracyBaseline {
    /// Compares a fresh run with this baseline over the samples they share, reporting the rest.
    public func compare(
        with report: TranscriptionReport, tolerance: RegressionTolerance = .standard
    ) -> BaselineComparison {
        let after = Dictionary(report.scores.map { ($0.caseID, BaselineEntry($0)) }) { first, _ in first }
        let before = Dictionary(entries.map { ($0.caseID, $0) }) { first, _ in first }
        let shared = Set(before.keys).intersection(after.keys).sorted()

        let mismatch = incomparability(with: report, shared: shared)
        let sharedBefore = shared.compactMap { before[$0] }
        let sharedAfter = shared.compactMap { after[$0] }

        return BaselineComparison(
            baselineLabel: label,
            overall: change("overall", sharedBefore, sharedAfter, tolerance),
            byLanguage: TranscriptionCase.Language.allCases.compactMap { language in
                slice(language.rawValue, sharedBefore, sharedAfter, tolerance) { $0.language == language }
            },
            byStress: Set(sharedBefore.flatMap(\.stresses)).sorted().compactMap { label in
                slice(label, sharedBefore, sharedAfter, tolerance) { $0.stresses.contains(label) }
            },
            byCohort: Set(sharedBefore.map(\.cohortLabel)).sorted().compactMap { label in
                slice(label, sharedBefore, sharedAfter, tolerance) { $0.cohortLabel == label }
            },
            regressed: movedSamples(shared, before, after, tolerance, worse: true),
            improved: movedSamples(shared, before, after, tolerance, worse: false),
            added: after.keys.filter { before[$0] == nil }.sorted(),
            removed: before.keys.filter { after[$0] == nil }.sorted(),
            newlyUnscorable: shared.filter {
                after[$0]?.isUnscorable == true && before[$0]?.isUnscorable == false
            },
            reason: mismatch
        )
    }

    /// Why these two runs are not about the same thing, if they are not; growth is not a reason.
    private func incomparability(with report: TranscriptionReport, shared: [String]) -> String? {
        if shared.isEmpty {
            return "the baseline and this run share no samples"
        }
        if !report.normalisation.isEmpty, report.normalisation != normalisation {
            return "the normalisation rules changed since the baseline, so the rates are not comparable"
        }
        return nil
    }

    private func change(
        _ label: String, _ before: [BaselineEntry], _ after: [BaselineEntry],
        _ tolerance: RegressionTolerance
    ) -> BaselineComparison.Change {
        let words = after.reduce(0) { $0 + $1.referenceWordCount }
        let beforeRate = rate(of: before)
        let afterRate = rate(of: after)
        let underpowered = words < tolerance.minimumReferenceWords
        return BaselineComparison.Change(
            label: label, before: beforeRate, after: afterRate, referenceWordCount: words,
            verdict: underpowered ? .unchanged : verdict(beforeRate, afterRate, tolerance),
            isUnderpowered: underpowered)
    }

    private func slice(
        _ label: String, _ before: [BaselineEntry], _ after: [BaselineEntry],
        _ tolerance: RegressionTolerance, matching: (BaselineEntry) -> Bool
    ) -> BaselineComparison.Change? {
        let matchedBefore = before.filter(matching)
        guard !matchedBefore.isEmpty else { return nil }
        return change(label, matchedBefore, after.filter(matching), tolerance)
    }

    /// Individual samples that moved, judged without the word-count floor, as evidence not verdict.
    private func movedSamples(
        _ shared: [String], _ before: [String: BaselineEntry], _ after: [String: BaselineEntry],
        _ tolerance: RegressionTolerance, worse: Bool
    ) -> [BaselineComparison.Change] {
        shared.compactMap { caseID -> BaselineComparison.Change? in
            guard let was = before[caseID]?.rate, let now = after[caseID]?.rate else { return nil }
            let moved = verdict(was, now, tolerance)
            guard moved == (worse ? .worsened : .improved) else { return nil }
            return BaselineComparison.Change(
                label: caseID, before: was, after: now,
                referenceWordCount: after[caseID]?.referenceWordCount ?? 0, verdict: moved)
        }
        .sorted { abs($0.delta ?? 0) > abs($1.delta ?? 0) }
    }

    private func rate(of entries: [BaselineEntry]) -> Double? {
        let words = entries.reduce(0) { $0 + $1.referenceWordCount }
        guard words > 0 else { return nil }
        return Double(entries.reduce(0) { $0 + $1.errors }) / Double(words)
    }

    private func verdict(
        _ before: Double?, _ after: Double?, _ tolerance: RegressionTolerance
    ) -> BaselineComparison.Verdict {
        guard let before, let after else { return .unchanged }
        let moved = (after - before) * 100
        if moved > tolerance.percentagePoints { return .worsened }
        if moved < -tolerance.percentagePoints { return .improved }
        return .unchanged
    }
}
