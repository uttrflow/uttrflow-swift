import Foundation
import Testing

@testable import UttrflowEval

@Suite("Accuracy comparison count validation")
struct AccuracyBaselineCountValidationTests {
    enum Location: CaseIterable {
        case clean, degraded, unscorable, nonshared
    }

    private func entry(
        _ id: String, errors: Int = 0, words: Int = 10, unscorable: Bool = false,
        condition: String? = nil
    ) -> BaselineEntry {
        BaselineEntry(
            caseID: id, language: .english, stresses: [], cohortID: nil, errors: errors,
            referenceWordCount: words, isUnscorable: unscorable, condition: condition)
    }

    private func baseline(_ entries: [BaselineEntry], label: String = "synthetic") -> AccuracyBaseline {
        AccuracyBaseline(
            label: label, recordedAt: Date(timeIntervalSince1970: 0), normalisation: [], entries: entries)
    }

    @Test(
        "negative counts anywhere in either report refuse a verdict", arguments: [false, true],
        Location.allCases)
    func negativeCounts(inBaseline: Bool, location: Location) {
        for negativeErrors in [false, true] {
            let shared = [entry("first"), entry("second")]
            let valid = entry(
                "invalid", unscorable: location == .unscorable,
                condition: location == .degraded ? "noise" : nil)
            let invalid = entry(
                "invalid", errors: negativeErrors ? -1 : 0, words: negativeErrors ? 10 : -1,
                unscorable: location == .unscorable,
                condition: location == .degraded ? "noise" : nil)
            let good = baseline(shared + (location == .nonshared ? [] : [valid]))
            let bad = baseline(shared + [invalid])
            let comparison = inBaseline ? bad.compare(with: good) : good.compare(with: bad)
            #expect(comparison.verdict == .incomparable)
            #expect(comparison.failsGate)
        }
    }

    @Test("a duplicate identifier cannot hide negative counts", arguments: [false, true])
    func duplicateCounts(inBaseline: Bool) {
        for negativeErrors in [false, true] {
            let shared = [entry("first"), entry("second")]
            let good = baseline(shared)
            let bad = baseline(
                shared + [entry("first", errors: negativeErrors ? -1 : 0, words: negativeErrors ? 10 : -1)])
            let comparison = inBaseline ? bad.compare(with: good) : good.compare(with: bad)
            #expect(comparison.verdict == .incomparable)
            #expect(comparison.failsGate)
        }
    }

    @Test("zero counts and unscorable entries keep their existing verdict", arguments: [false, true])
    func zeroCounts(unscorable: Bool) {
        let run = baseline([entry("zero", words: 0, unscorable: unscorable)])
        let comparison = run.compare(with: run)
        #expect(comparison.verdict == .unchanged)
        #expect(!comparison.failsGate)
        #expect(comparison.overall.before == nil)
        #expect(comparison.overall.interval == nil)
    }

    @Test("one scored utterance keeps its underpowered comparison")
    func underpowered() {
        let comparison = baseline([entry("single")]).compare(with: baseline([entry("single", errors: 1)]))
        #expect(comparison.verdict == .unchanged)
        #expect(!comparison.failsGate)
        #expect(comparison.overall.after == 0.1)
        #expect(comparison.overall.isUnderpowered)
    }

    @Test("insertions can exceed the reference count")
    func insertionHeavy() {
        let run = baseline([entry("first", errors: 20), entry("second", errors: 20)])
        let comparison = run.compare(with: run)
        #expect(comparison.verdict == .unchanged)
        #expect(!comparison.failsGate)
        #expect(comparison.overall.after == 2)
    }

    @Test("existing label mismatch keeps precedence over invalid counts")
    func mismatchPrecedence() {
        let comparison = baseline([entry("first")]).compare(
            with: baseline([entry("first", errors: -1)], label: "other"))
        #expect(
            comparison.reason
                == "the baseline measured synthetic and this run measured other, so the rates are not comparable"
        )
        #expect(comparison.failsGate)
    }
}
