import Foundation
import Testing

@testable import UttrflowEval

@Suite("The regression gate")
struct AccuracyBaselineTests {
    private let moment = Date(timeIntervalSince1970: 1_700_000_000)

    private func report(_ scores: [PassageScore], label: String = "whisperKit tiny") -> TranscriptionReport {
        TranscriptionReport(label: label, scores: scores)
    }

    /// Twenty reference words a sample, so a corpus of a handful of samples clears the
    /// word-count floor and the verdicts under test are about accuracy rather than size.
    private func sample(
        _ id: String,
        errors: Int,
        language: TranscriptionCase.Language = .english,
        stresses: [String] = ["punctuation"],
        cohort: String? = "naveen-quiet",
        words: Int = 400
    ) -> PassageScore {
        let reference = (1...words).map { "w\($0)" }
        var heard = reference
        for index in 0..<errors { heard[index] = "wrong\(index)" }
        return score(
            id, language: language, stresses: stresses, cohort: cohort, reference: reference, heard: heard)
    }

    // MARK: Capturing

    /// Errors and words rather than a rate: a stored rate cannot be re-aggregated, and
    /// storing both is how the two come to disagree.
    @Test("keeps the counts a rate is made of, not the rate")
    func captures() {
        let baseline = AccuracyBaseline.capture(report([sample("a", errors: 5, words: 100)]), at: moment)
        #expect(baseline.entries.count == 1)
        #expect(baseline.entries[0].errors == 5)
        #expect(baseline.entries[0].referenceWordCount == 100)
        #expect(baseline.entries[0].rate == 0.05)
        #expect(baseline.entries[0].id == "a")
        #expect(baseline.label == "whisperKit tiny")
        #expect(baseline.id == "whisperKit tiny")
    }

    @Test("an unscorable sample has no rate and is marked as such")
    func unscorable() {
        let failed = score("a", reference: [], heard: [], failure: .audioUnreadable("gone"))
        let baseline = AccuracyBaseline.capture(report([failed]), at: moment)
        #expect(baseline.entries[0].isUnscorable)
        #expect(baseline.entries[0].rate == nil)
    }

    /// A baseline is meant to be committed and reviewed, so two captures of the same
    /// corpus have to produce the same bytes.
    @Test("writes a stable, sorted file and reads it back")
    func roundTrips() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: AccuracyBaseline.defaultFileName)
        let baseline = AccuracyBaseline.capture(
            report([sample("z", errors: 1), sample("a", errors: 2)]), at: moment)

        try baseline.write(to: url)
        let read = try AccuracyBaseline.read(from: url)
        #expect(read == baseline)
        #expect(read.entries.map(\.caseID) == ["a", "z"])
        #expect(read.recordedAt == moment)
    }

    @Test("says what it could not read or write")
    func reportsStoreFailures() {
        #expect(throws: EvaluationStoreError.self) {
            try AccuracyBaseline.read(from: temporaryDirectory().appending(path: "nothing.json"))
        }
        let file = temporaryDirectory().appending(path: "occupied")
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(throws: EvaluationStoreError.self) {
            try AccuracyBaseline.capture(report([]), at: moment)
                .write(to: file.appending(path: "under/baseline.json"))
        }
    }

    // MARK: Comparing

    @Test("says nothing changed when nothing changed")
    func unchanged() {
        let baseline = AccuracyBaseline.capture(report([sample("a", errors: 5)]), at: moment)
        let comparison = baseline.compare(with: report([sample("a", errors: 5)]))
        #expect(comparison.verdict == .unchanged)
        #expect(!comparison.isRegression)
        #expect(comparison.overall.delta == 0)
    }

    @Test("notices an improvement, and calls it one")
    func improvement() {
        let baseline = AccuracyBaseline.capture(report([sample("a", errors: 10)]), at: moment)
        let comparison = baseline.compare(with: report([sample("a", errors: 2)]))
        #expect(comparison.verdict == .improved)
        #expect(comparison.improved.map(\.label) == ["a"])
        #expect(comparison.overall.before == 0.025)
        #expect(comparison.overall.after == 0.005)
    }

    @Test("notices a regression, and refuses to pass")
    func regression() {
        let baseline = AccuracyBaseline.capture(report([sample("a", errors: 2)]), at: moment)
        let comparison = baseline.compare(with: report([sample("a", errors: 20)]))
        #expect(comparison.verdict == .worsened)
        #expect(comparison.isRegression)
        #expect(comparison.regressed.map(\.label) == ["a"])
    }

    /// The entire point of not pooling. An engine that gets better at English and worse
    /// at Hinglish has not got better, and a headline figure would say it had.
    @Test("a slice going backwards is a regression even when the headline improves")
    func aSliceCanFailAlone() {
        let before = report([
            sample("en", errors: 300, language: .english, words: 2_000),
            sample("hi", errors: 2, language: .hinglish, words: 400),
        ])
        let after = report([
            sample("en", errors: 5, language: .english, words: 2_000),
            sample("hi", errors: 40, language: .hinglish, words: 400),
        ])
        let comparison = AccuracyBaseline.capture(before, at: moment).compare(with: after)

        #expect(comparison.overall.verdict == .improved, "the pooled figure got better")
        #expect(comparison.verdict == .worsened, "and one language got much worse")
        let hinglish = comparison.byLanguage.first { $0.label == "hinglish" }
        #expect(hinglish?.verdict == .worsened)
    }

    @Test("reports each axis separately: language, stress and cohort")
    func everyAxis() {
        let before = report([
            sample("a", errors: 2, language: .english, stresses: ["accent"], cohort: "naveen-quiet"),
            sample("b", errors: 2, language: .hindi, stresses: ["punctuation"], cohort: "priya-cafe"),
        ])
        let after = report([
            sample("a", errors: 2, language: .english, stresses: ["accent"], cohort: "naveen-quiet"),
            sample("b", errors: 30, language: .hindi, stresses: ["punctuation"], cohort: "priya-cafe"),
        ])
        let comparison = AccuracyBaseline.capture(before, at: moment).compare(with: after)
        #expect(comparison.byLanguage.map(\.label) == ["english", "hindi"])
        #expect(comparison.byStress.map(\.label) == ["accent", "punctuation"])
        #expect(comparison.byCohort.map(\.label) == ["naveen-quiet", "priya-cafe"])
        #expect(comparison.byCohort.first { $0.label == "priya-cafe" }?.verdict == .worsened)
        #expect(comparison.byCohort.first { $0.label == "naveen-quiet" }?.verdict == .unchanged)
    }

    /// A rule that fired on noise would be switched off within a week, which is the real
    /// failure mode of an accuracy gate.
    @Test("a move smaller than the tolerance is not a finding")
    func tolerance() {
        let baseline = AccuracyBaseline.capture(report([sample("a", errors: 5, words: 1_000)]), at: moment)
        // Two more errors in a thousand words is 0.2 points, under the half-point default.
        #expect(baseline.compare(with: report([sample("a", errors: 7, words: 1_000)])).verdict == .unchanged)
        // And a caller who wants a stricter gate can have one.
        let strict = RegressionTolerance(percentagePoints: 0.1)
        #expect(
            baseline.compare(with: report([sample("a", errors: 7, words: 1_000)]), tolerance: strict).verdict
                == .worsened)
    }

    /// A cohort of two short samples will swing ten points on one misheard name. It is
    /// still shown — silence about a slice is worse than caution about it.
    @Test("a slice too small to judge is reported, not ruled on")
    func underpowered() {
        let before = report([sample("a", errors: 0, cohort: "tiny", words: 10)])
        let after = report([sample("a", errors: 5, cohort: "tiny", words: 10)])
        let comparison = AccuracyBaseline.capture(before, at: moment).compare(with: after)
        #expect(comparison.overall.isUnderpowered)
        #expect(comparison.overall.verdict == .unchanged)
        // The sample itself still shows the movement, as evidence rather than a verdict.
        #expect(comparison.regressed.map(\.label) == ["a"])
    }

    /// The corpus is meant to grow to a thousand. A gate that refused to judge whenever a
    /// sample was added would never judge anything.
    @Test("compares the samples the two runs share, and says what changed around them")
    func aGrowingCorpus() {
        let before = report([sample("a", errors: 5), sample("gone", errors: 5)])
        let after = report([sample("a", errors: 5), sample("new", errors: 90)])
        let comparison = AccuracyBaseline.capture(before, at: moment).compare(with: after)

        #expect(comparison.added == ["new"])
        #expect(comparison.removed == ["gone"])
        #expect(comparison.overall.referenceWordCount == 400, "only the shared sample counts")
        #expect(comparison.verdict == .unchanged, "the new sample is not evidence about a change")
    }

    @Test("refuses a verdict when the two runs share nothing")
    func noOverlap() {
        let comparison = AccuracyBaseline.capture(report([sample("a", errors: 1)]), at: moment)
            .compare(with: report([sample("b", errors: 1)]))
        #expect(comparison.verdict == .incomparable)
        #expect(comparison.reason?.contains("share no samples") == true)
    }

    /// The same transcripts score differently under different rules, so a comparison
    /// across a normalisation change is not a comparison.
    @Test("refuses a verdict when the normalisation rules changed")
    func changedNormalisation() {
        let before = report([sample("a", errors: 5)])
        let looser = PassageScore(
            caseID: "a", language: .english, stressor: .everyday,
            wordErrorRate: .measure(reference: ["one"], hypothesis: ["one"]),
            answeredIn: .latin, scoredAgainst: .latin, normalisation: [.caseFolding])
        let comparison = AccuracyBaseline.capture(before, at: moment)
            .compare(with: report([looser]))
        #expect(comparison.verdict == .incomparable)
        #expect(comparison.reason?.contains("normalisation") == true)
    }

    /// A run where forty samples stopped producing a transcript has got worse even if
    /// every surviving rate improved.
    @Test("a sample that stopped being scorable is a regression")
    func newlyUnscorable() {
        let before = report([sample("a", errors: 5), sample("b", errors: 5)])
        let broken = score("b", reference: [], heard: [], failure: .audioUnreadable("gone"))
        let comparison = AccuracyBaseline.capture(before, at: moment)
            .compare(with: report([sample("a", errors: 0), broken]))
        #expect(comparison.newlyUnscorable == ["b"])
        #expect(comparison.verdict == .worsened)
    }

    @Test("lists the samples that moved most, worst first")
    func ranksMovedSamples() {
        let before = report([
            sample("small", errors: 5), sample("big", errors: 5), sample("steady", errors: 5),
        ])
        let after = report([
            sample("small", errors: 8), sample("big", errors: 50), sample("steady", errors: 5),
        ])
        let comparison = AccuracyBaseline.capture(before, at: moment).compare(with: after)
        #expect(comparison.regressed.map(\.label) == ["big", "small"])
        // 5 errors in 400 words to 50: 1.25% to 12.5%.
        #expect(comparison.regressed.first?.delta == 0.1125)
    }

    @Test("a change with no rate on one side has no delta to report")
    func missingRates() {
        let change = BaselineComparison.Change(
            label: "x", before: nil, after: 0.1, referenceWordCount: 0, verdict: .unchanged)
        #expect(change.delta == nil)
        #expect(change.id == "x")
    }
}
