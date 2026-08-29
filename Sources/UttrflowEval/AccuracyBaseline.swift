public import Foundation

/// One sample's contribution to a run, kept so any slice of it can be recomputed later.
///
/// Errors and reference words rather than a rate. A stored rate cannot be re-aggregated
/// — adding percentages is how a corpus average goes wrong — and storing both the rate
/// and the counts is how the two come to disagree. From these two numbers every figure
/// in a comparison can be derived exactly, including slices nobody thought to store.
public struct BaselineEntry: Sendable, Equatable, Codable, Identifiable {
    public var id: String { caseID }
    public let caseID: String
    public let language: TranscriptionCase.Language
    public let stresses: [String]
    public let cohortID: String?
    public let errors: Int
    public let referenceWordCount: Int
    /// The passage produced nothing to score. Counted separately: a run where forty
    /// samples stopped being scorable has got worse even if every remaining rate
    /// improved, and a comparison that only looked at rates would call that progress.
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
}

/// What accuracy was, on a day somebody decided it was good enough to hold on to.
///
/// The thing that stops the product getting worse while appearing to get smarter. Every
/// change to the recogniser, the normalisation, the model or the prompt moves some
/// samples up and some down, and without a stored point of comparison the only available
/// evidence is a number that looks fine on its own. Correction work in particular cannot
/// be done without this: a dictionary entry that fixes one name and breaks four others is
/// indistinguishable from one that works, until you can diff.
public struct AccuracyBaseline: Sendable, Equatable, Codable, Identifiable {
    public var id: String { label }
    /// What was measured: engine, model, whether the language was hinted. Two baselines
    /// with different labels describe different things and must not be compared.
    public let label: String
    public let recordedAt: Date
    /// The rules the rates were measured under. A comparison across two different sets
    /// of normalisation rules is not a comparison, and this is what lets one be refused.
    public let normalisation: [NormalisationRule]
    public let entries: [BaselineEntry]

    public init(
        label: String, recordedAt: Date, normalisation: [NormalisationRule], entries: [BaselineEntry]
    ) {
        self.label = label
        self.recordedAt = recordedAt
        self.normalisation = normalisation
        // Sorted so two baselines over the same corpus are byte-identical files, which
        // makes them diffable and reviewable in the same way as any other source.
        self.entries = entries.sorted { $0.caseID < $1.caseID }
    }

    public static func capture(_ report: TranscriptionReport, at moment: Date = Date()) -> AccuracyBaseline {
        AccuracyBaseline(
            label: report.label, recordedAt: moment, normalisation: report.normalisation,
            entries: report.scores.map(BaselineEntry.init))
    }

    // MARK: On disk

    /// Written where it can be committed, unlike the results it came from.
    ///
    /// A baseline that lives only on the machine that produced it cannot gate anything:
    /// the point is that somebody else's change is measured against it.
    public static let defaultFileName = "accuracy-baseline.json"

    public func write(to url: URL) throws(EvaluationStoreError) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
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

/// How much movement counts as movement.
///
/// Without this a gate fires on noise. Two runs of the same model over the same audio can
/// differ by a word, and a rule that called that a regression would be switched off
/// within a week — which is the real failure mode of an accuracy gate, not a missed
/// regression.
public struct RegressionTolerance: Sendable, Equatable {
    /// How far a rate may move before it is a finding, in percentage points.
    public let percentagePoints: Double
    /// How much a slice has to rest on before it is judged at all.
    ///
    /// A cohort of two short samples will swing by ten points on one misheard name. It
    /// is still reported — silence about a slice is worse than caution about it — but as
    /// "too small to judge" rather than as a verdict.
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
        /// How much the slice rests on now. Reported beside every delta, because a
        /// three-point move over sixty words is not the same finding as the same move
        /// over six thousand.
        public let referenceWordCount: Int
        public let verdict: Verdict
        /// The slice is too small to judge, so its verdict is ``Verdict/unchanged`` by
        /// default rather than by evidence.
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
    /// Samples in the new run that the baseline never saw, and the other way round. The
    /// corpus is meant to grow, so this is information rather than a problem — but every
    /// figure above is computed over the samples the two runs share, and that has to be
    /// visible or the numbers are quietly about different corpora.
    public let added: [String]
    public let removed: [String]
    /// Samples that used to produce a transcript and now produce nothing.
    public let newlyUnscorable: [String]
    public let reason: String?

    public var verdict: Verdict {
        if reason != nil { return .incomparable }
        // Any judged slice going backwards is a regression, even when the headline
        // improved. That is the entire point of not pooling: an engine that gets better
        // at English and worse at Hinglish has not got better.
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
    /// Compares a fresh run with this baseline.
    ///
    /// Computed over the samples the two have in common, with everything else reported
    /// rather than folded in. A corpus that is meant to reach a thousand samples grows
    /// between every pair of runs, and a gate that refused to judge whenever a sample was
    /// added would never judge anything; a gate that quietly compared eight hundred
    /// samples against nine hundred would be worse still.
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
            byCohort: Set(sharedBefore.map { $0.cohortID ?? RecordingCohort.unattributed }).sorted()
                .compactMap { label in
                    slice(label, sharedBefore, sharedAfter, tolerance) {
                        ($0.cohortID ?? RecordingCohort.unattributed) == label
                    }
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

    /// Why these two runs cannot be compared at all, if they cannot.
    ///
    /// Only two reasons, and both of them are "these numbers are not about the same
    /// thing". Everything else — a bigger corpus, a new cohort, a sample retired — is a
    /// difference the comparison handles rather than refuses.
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

    /// Individual samples that moved, so a regression can be looked at rather than
    /// argued about. Judged per sample without the word-count floor: one passage is
    /// always a small sample, and the list is evidence rather than a verdict.
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
