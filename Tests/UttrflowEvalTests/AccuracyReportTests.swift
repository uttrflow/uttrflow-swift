// Tests the per-release accuracy report and the history it compares against.
import Foundation
import Testing
import UttrflowTestSupport

@testable import UttrflowEval

@Suite("The release accuracy report")
struct AccuracyReportTests {
    /// The recorded report for the fixture below, beside this file.
    static let golden = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent()
        .appendingPathComponent("Golden/accuracy-report.golden")

    private static func entry(
        _ id: String, errors: Int, words: Int, stress: String, cohort: String = "synthesised-example",
        language: TranscriptionCase.Language = .english
    ) -> BaselineEntry {
        BaselineEntry(
            caseID: id, language: language, stresses: [stress], cohortID: cohort, errors: errors,
            referenceWordCount: words, isUnscorable: false, recordingIdentity: "sha256:\(id)")
    }

    private static func baseline(_ entries: [BaselineEntry], day: Double) -> AccuracyBaseline {
        AccuracyBaseline(
            label: "fixture recogniser", recogniser: "fixture-pin",
            recordedAt: Date(timeIntervalSince1970: day * 86_400),
            normalisation: [.caseFolding, .numberWords], entries: entries)
    }

    static let earlier = baseline(
        [
            entry("a", errors: 4, words: 60, stress: "everyday"),
            entry("b", errors: 2, words: 60, stress: "everyday"),
            entry("c", errors: 6, words: 50, stress: "technical"),
        ], day: 20_000)

    static let current = baseline(
        [
            entry("a", errors: 1, words: 60, stress: "everyday"),
            entry("b", errors: 2, words: 60, stress: "everyday"),
            entry("c", errors: 3, words: 50, stress: "technical"),
            entry("d", errors: 0, words: 40, stress: "digits"),
        ], day: 20_010)

    static var report: AccuracyReport {
        AccuracyReport(
            version: "26.1007.0", baseline: current,
            history: AccuracyHistory(releases: [.init(version: "26.0926.0", baseline: earlier)]))
    }

    @Test("a fixture baseline renders the recorded report, byte for byte")
    func matchesGolden() throws {
        let generated = Self.report.markdown
        let environment = ProcessInfo.processInfo.environment
        if environment[GoldenFile.updateVariable] == "1", environment["CI"] == nil {
            try generated.write(to: Self.golden, atomically: true, encoding: .utf8)
        }
        let recorded = try String(contentsOf: Self.golden, encoding: .utf8)
        #expect(recorded == generated, "rerun with \(GoldenFile.updateVariable)=1 to regenerate the report")
        #expect(Self.report.markdown == generated, "the same inputs render the same report")
    }

    @Test("a slice under the minimum reference words is printed as too small to judge, with its counts")
    func smallSlice() throws {
        let line = try #require(
            Self.report.markdown.split(separator: "\n").first { $0.hasPrefix("| technical |") })
        #expect(line == "| technical | 1 | 50 | 3 | too small to judge | – |")
        let judged = try #require(
            Self.report.markdown.split(separator: "\n").first { $0.hasPrefix("| everyday |") })
        #expect(!judged.contains("too small"))
    }

    @Test("rates are given per slice and never pooled into one headline")
    func neverPooled() {
        #expect(!Self.report.markdown.contains("| overall |"))
    }

    @Test("with no earlier release the report says so instead of comparing")
    func firstRelease() {
        let report = AccuracyReport(version: "26.1007.0", baseline: Self.current, history: AccuracyHistory())
        #expect(report.previous == nil)
        #expect(report.markdown.contains("No earlier release is in the history."))
    }

    @Test("the previous release is the latest other version, so a re-run does not compare with itself")
    func previousSkipsItself() {
        let history = AccuracyHistory(releases: [
            .init(version: "26.0926.0", baseline: Self.earlier),
            .init(version: "26.1007.0", baseline: Self.current),
        ])
        #expect(
            AccuracyReport(version: "26.1007.0", baseline: Self.current, history: history).previous?.version
                == "26.0926.0")
    }

    @Test("a different recogniser is named as the reason, not compared")
    func incomparable() {
        let other = AccuracyBaseline(
            label: "another recogniser", recogniser: "fixture-pin", recordedAt: Self.earlier.recordedAt,
            normalisation: Self.earlier.normalisation, entries: Self.earlier.entries)
        let report = AccuracyReport(
            version: "26.1007.0", baseline: Self.current,
            history: AccuracyHistory(releases: [.init(version: "26.0926.0", baseline: other)]))
        #expect(report.markdown.contains("Not compared: the baseline measured another recogniser"))
    }

    @Test("the history gains one line per release, and recording a version again replaces its line")
    func historyLines() throws {
        var history = AccuracyHistory()
        #expect(history.fileContents == "[]\n")
        history.record(.init(version: "26.0926.0", baseline: Self.earlier))
        history.record(.init(version: "26.1007.0", baseline: Self.current))
        history.record(.init(version: "26.1007.0", baseline: Self.current))
        let lines = history.fileContents.split(separator: "\n")
        #expect(lines.count == 4)
        #expect(history.releases.map(\.version) == ["26.0926.0", "26.1007.0"])

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try AccuracyHistory.read(from: url) == AccuracyHistory())
        try history.write(to: url)
        #expect(try AccuracyHistory.read(from: url) == history)
    }

    @Test("an unreadable history is an error, not an empty history")
    func unreadableHistory() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        #expect(throws: EvaluationStoreError.self) { try AccuracyHistory.read(from: url) }
    }

    @Test("the corpus digest moves when a case's recording does")
    func corpusDigest() {
        let retaken = BaselineEntry(
            caseID: "d", language: .english, stresses: ["digits"], cohortID: "synthesised-example", errors: 0,
            referenceWordCount: 40, isUnscorable: false, recordingIdentity: "sha256:retaken")
        let moved = AccuracyBaseline(
            label: Self.current.label, recogniser: Self.current.recogniser,
            recordedAt: Self.current.recordedAt,
            normalisation: Self.current.normalisation, entries: Self.current.entries.dropLast() + [retaken])
        let report = AccuracyReport(version: "x", baseline: moved, history: AccuracyHistory())
        #expect(Self.report.corpusDigest.hasPrefix("sha256:"))
        #expect(report.corpusDigest != Self.report.corpusDigest)
    }
}
