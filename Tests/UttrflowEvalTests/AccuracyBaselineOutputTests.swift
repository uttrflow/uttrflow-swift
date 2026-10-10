// Tests that the regression gate judges the romanised output of a Devanagari answer.
import Foundation
import Testing
import UttrflowCore

@testable import UttrflowEval

@Suite("The regression gate on romanised output")
struct AccuracyBaselineOutputTests {
    private let moment = Date(timeIntervalSince1970: 1_700_000_000)

    private func rate(errors: Int, words: Int = 400) -> WordErrorRate {
        let reference = (1...words).map { "w\($0)" }
        var heard = reference
        for index in 0..<errors { heard[index] = "wrong\(index)" }
        return .measure(reference: reference, hypothesis: heard)
    }

    /// Hindi passages the recogniser heard equally well, with `outputErrors` in the romanised text, or none scored.
    private func report(outputErrors: Int?) -> TranscriptionReport {
        let scores = (1...3).map { index in
            PassageScore(
                caseID: "hi\(index)", language: .hindi, stressor: .everyday,
                wordErrorRate: rate(errors: 2), answeredIn: .devanagari, scoredAgainst: .devanagari,
                outputWordErrorRate: outputErrors.map { rate(errors: $0) })
        }
        return TranscriptionReport(label: "probe", scores: scores)
    }

    @Test("a broken romaniser fails the gate while the recogniser rate is unchanged")
    func romaniserBreakFailsGate() {
        let baseline = AccuracyBaseline.capture(report(outputErrors: 2), at: moment)
        let broken = report(outputErrors: 40)
        #expect(baseline.entries.allSatisfy { $0.scoresOutput })
        #expect(broken.wordErrorRate(in: .hindi) == report(outputErrors: 2).wordErrorRate(in: .hindi))
        let comparison = baseline.compare(with: broken)
        #expect(comparison.verdict == .worsened)
        #expect(comparison.failsGate)
    }

    @Test("a baseline of recogniser counts is not compared with a run of output counts")
    func refusesMixedTexts() {
        let baseline = AccuracyBaseline.capture(report(outputErrors: nil), at: moment)
        let comparison = baseline.compare(with: report(outputErrors: 2))
        #expect(comparison.verdict == .incomparable)
        #expect(comparison.reason?.contains("romanised output") == true)
    }

    @Test("a baseline saved before output scoring reads as recogniser counts")
    func legacyEntryDecodes() throws {
        let legacy = Data(
            """
            {"caseID":"en-a","language":"english","stresses":["everyday"],"errors":1,
             "referenceWordCount":50,"isUnscorable":false}
            """.utf8)
        let entry = try JSONDecoder().decode(BaselineEntry.self, from: legacy)
        #expect(!entry.scoresOutput)
        #expect(entry.cohortID == nil)
        let reread = try JSONDecoder().decode(BaselineEntry.self, from: JSONEncoder().encode(entry))
        #expect(reread == entry)
    }
}
