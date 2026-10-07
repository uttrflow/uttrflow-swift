import Testing
import UttrflowEval
@testable import uttrflow_bakeoff

struct TidyCueTests {
    @Test("each cue is read from the pass that acted on the words")
    func readsThePassThatActed() {
        #expect(TidyCue.cues(in: "um send the report").contains(.filler))
        #expect(TidyCue.cues(in: "send the the report").contains(.repeated))
        #expect(TidyCue.cues(in: "send it to Tom no wait to Ana").contains(.repair))
        #expect(TidyCue.cues(in: "send the report today") == [])
    }

    @Test("a long dictation with no inner stop is a run-on, and a short or stopped one is not")
    func runOn() {
        let long = Array(repeating: "word", count: TidyCue.runOnWords)
        #expect(TidyCue.isRunOn(long))
        #expect(!TidyCue.isRunOn(Array(long.dropLast())))
        var stopped = long
        stopped[3] = "word."
        #expect(!TidyCue.isRunOn(stopped))
    }
}

struct TidyGateReportTests {
    private func row(
        _ cues: Set<TidyCue>, words: Int, rules: Bool, model: Bool, seconds: Double
    ) -> TidyGateRow {
        TidyGateRow(
            category: "everyday", cues: cues, words: words, rulesPassed: rules, modelPassed: model,
            rulesSeconds: 0, modelSeconds: seconds)
    }

    @Test("the gate skips cue-free cases, keeps their rules result and drops their model time")
    func gateSkipsCueFreeCases() {
        let rows = [
            row([.filler], words: 10, rules: false, model: true, seconds: 1),
            row([], words: 10, rules: true, model: true, seconds: 2),
            row([], words: 80, rules: true, model: false, seconds: 3),
        ]
        #expect(rows.map(\.callsModel) == [true, false, false])
        #expect(rows.map(\.gatedPassed) == [true, true, true])
        #expect(rows.map(\.gatedSeconds) == [1, 0, 0])
        let lines = TidyGateReport(rows: rows).lines.joined(separator: "\n")
        #expect(lines.contains("skips 2 of 3 (67%)"))
        #expect(lines.contains("cue filler"))
    }

    @Test("sampling takes the first cases of each category, and zero takes them all")
    func sampling() {
        let all = EvaluationCorpus.all
        #expect(TidyGate.sample(all, perCategory: 0).count == all.count)
        let one = TidyGate.sample(all, perCategory: 1)
        #expect(one.count == Set(all.map(\.category)).count)
    }

    @Test("quantiles are nearest-rank and an empty slice prints a dash")
    func quantiles() {
        #expect(TidyGateReport.seconds([], 0.5) == "—")
        #expect(TidyGateReport.seconds([1, 2, 3, 4], 0.5) == "2.00s")
        #expect(TidyGateReport.seconds([1, 2, 3, 4], 0.95) == "4.00s")
        #expect(TidyGateReport.share(1, 0) == 0)
    }
}
