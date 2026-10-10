// Tests the audio condition as its own axis of the accuracy baseline, never pooled with clean reads.
import Foundation
import Testing

@testable import UttrflowEval

@Suite("The condition axis of the regression gate")
struct ConditionAxisTests {
    private let moment = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(
        _ caseID: String, errors: Int, condition: String? = nil,
        language: TranscriptionCase.Language = .english, words: Int = 400
    ) -> BaselineEntry {
        BaselineEntry(
            caseID: caseID, language: language, stresses: ["everyday"], cohortID: "avery-quiet",
            errors: errors, referenceWordCount: words, isUnscorable: false, condition: condition)
    }

    /// Three passages, each read clean and replayed under white noise at 10 dB.
    private func baseline(clean: Int, noisy: Int) -> AccuracyBaseline {
        let passages = ["a1", "a2", "a3"]
        return AccuracyBaseline(
            label: "noise whisperKit tiny", recordedAt: moment, normalisation: [],
            entries: passages.map { entry($0, errors: clean) }
                + passages.map { entry($0, errors: noisy, condition: "white 10 dB") })
    }

    @Test("a passage replayed under a condition is its own entry, not a duplicate of the clean read")
    func keysByCondition() {
        let subject = baseline(clean: 2, noisy: 40)
        #expect(Set(subject.entries.map(\.id)).count == 6)
        #expect(subject.entries.first { $0.condition == nil }?.id == "a1")
        #expect(subject.entries.first { $0.condition != nil }?.id == "a1 @ white 10 dB")
    }

    @Test("the overall, language, stress and cohort slices hold clean reads only")
    func headlineIsClean() {
        let comparison = baseline(clean: 2, noisy: 2).compare(with: baseline(clean: 2, noisy: 60))
        #expect(comparison.overall.verdict == .unchanged)
        #expect(comparison.overall.referenceWordCount == 1_200)
        #expect(comparison.byLanguage.map(\.referenceWordCount) == [1_200])
        #expect(comparison.byStress.map(\.referenceWordCount) == [1_200])
        #expect(comparison.byCohort.map(\.referenceWordCount) == [1_200])
    }

    @Test("each condition is its own slice, and one going backwards fails the gate")
    func conditionSliceFailsAlone() {
        let comparison = baseline(clean: 2, noisy: 2).compare(with: baseline(clean: 2, noisy: 60))
        #expect(comparison.byCondition.map(\.label) == ["white 10 dB"])
        #expect(comparison.byCondition.first?.verdict == .worsened)
        #expect(comparison.verdict == .worsened)
        #expect(
            comparison.regressed.map(\.label) == ["a1 @ white 10 dB", "a2 @ white 10 dB", "a3 @ white 10 dB"])
    }

    @Test("a clean-only run has no condition slices")
    func cleanOnlyHasNoConditionSlices() {
        let clean = AccuracyBaseline(
            label: "x", recordedAt: moment, normalisation: [], entries: [entry("a", errors: 1)])
        #expect(clean.compare(with: clean).byCondition.isEmpty)
    }

    @Test("a baseline saved before the axis existed reads every entry as clean")
    func legacyEntriesAreClean() throws {
        let json = Data(
            """
            {"caseID":"a","language":"english","stresses":[],"errors":1,"referenceWordCount":10,"isUnscorable":false}
            """.utf8)
        let decoded = try JSONDecoder().decode(BaselineEntry.self, from: json)
        #expect(decoded.condition == nil)
        #expect(decoded.id == "a")
    }

    @Test("a degraded entry survives a write and a read")
    func roundTrips() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: AccuracyBaseline.defaultFileName)
        let subject = baseline(clean: 1, noisy: 9)
        try subject.write(to: url)
        #expect(try AccuracyBaseline.read(from: url) == subject)
    }

    @Test("the label yield a fit is planned from counts clean reads only")
    func fitYieldIsClean() {
        let yields = LabelYield.measure(baseline(clean: 2, noisy: 200))
        #expect(yields.map(\.errors) == [6])
        #expect(yields.map(\.words) == [1_200])
    }
}
