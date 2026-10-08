// Tests that the tidy tally counts each engine's outcomes exactly over a bounded window.
import Testing

@testable import UttrflowCore

@Suite("TidyTally")
struct TidyTallyTests {
    @Test("a scripted run of outcomes yields the exact counts")
    func countsAScriptedRun() {
        var tally = TidyTally()
        for _ in 0..<94 { tally.add(TidyOutcome(finishedBy: .localModel)) }
        for _ in 0..<4 {
            tally.add(
                TidyOutcome(
                    finishedBy: .rules, refusals: [.init(engine: .localModel, kind: .lostWord)]))
        }
        for _ in 0..<2 {
            tally.add(
                TidyOutcome(
                    finishedBy: .rules, failures: [.init(engine: .localModel, failureClass: .timedOut)],
                    unavailable: [.init(engine: .foundationModels, reason: .modelNotReady)]))
        }
        tally.add(TidyOutcome(finishedBy: nil))

        let local = tally.counts[.localModel]
        #expect(local?.accepted == 94)
        let refused: [RefusalKind: Int] = [.lostWord: 4]
        let failed: [ModelFailureClass: Int] = [.timedOut: 2]
        let skipped: [TidyTally.UnavailableReason: Int] = [.modelNotReady: 2]
        #expect(local?.refused == refused)
        #expect(local?.failed == failed)
        #expect(tally.counts[.rules]?.accepted == 6)
        #expect(tally.counts[.foundationModels]?.unavailable == skipped)
        #expect(tally.untidied == 1)
        let lines: [String] = [
            "foundationModels: accepted 0, skipped modelNotReady 2",
            "localModel: accepted 94, refused lostWord 4, failed timedOut 2",
            "rules: accepted 6",
            "untidied: 1",
        ]
        #expect(tally.lines == lines)
    }

    @Test("the window drops the oldest piece beyond its capacity")
    func dropsTheOldest() {
        var tally = TidyTally()
        tally.add(TidyOutcome(finishedBy: .rules))
        for _ in 0..<TidyTally.capacity { tally.add(TidyOutcome(finishedBy: .localModel)) }

        #expect(tally.outcomes.count == TidyTally.capacity)
        #expect(tally.counts[.rules] == nil)
        #expect(tally.counts[.localModel]?.accepted == TidyTally.capacity)
    }

    @Test("a record's free-text skip reason is folded into a closed name")
    func foldsFreeText() {
        let record = CleaningRecord(
            changes: [],
            unavailableEngines: [.init(engine: "foundationModels", reason: .other("zorblaxquent"))])
        var tally = TidyTally()
        tally.add(TidyOutcome(finishedBy: .rules, record: record))

        let other: [TidyTally.UnavailableReason: Int] = [.other: 1]
        #expect(tally.counts[.foundationModels]?.unavailable == other)
        #expect(!tally.lines.joined().contains("zorblaxquent"))
    }
}
