// Tests for the pair ledger: a pair becomes an entry only by recurrence on separate days.

import UttrflowCore
import Testing

@testable import UttrflowDictionary

@Suite("Pair ledger")
struct PairLedgerTests {
    private func record(
        _ ledger: inout PairLedger, _ heard: String, _ meant: String, day: Int, times: Int = 1
    )
        -> [ConfusionPairs.Pair]
    {
        (0..<times).compactMap { _ in ledger.record(heard: heard, meant: meant, on: day).learnt }
    }

    @Test("One sighting learns nothing")
    func once() {
        var ledger = PairLedger()
        let found = record(&ledger, "kemma", "Gemma", day: 100)
        #expect(found.isEmpty)
        #expect(ledger.pendingCount == 1)
    }

    @Test("Three sightings on one day learn nothing")
    func sameDay() {
        var ledger = PairLedger()
        let found = record(&ledger, "kemma", "Gemma", day: 100, times: 50)
        #expect(found.isEmpty)
    }

    @Test("Three sightings over two days learn one pair")
    func twoDays() {
        var ledger = PairLedger()
        let found = record(&ledger, "kemma", "Gemma", day: 100, times: 2)
        #expect(found.isEmpty)
        let learnt = record(&ledger, "kemma", "Gemma", day: 101)
        #expect(learnt == [ConfusionPairs.Pair(heard: "kemma", meant: "Gemma")])
        #expect(ledger.pendingCount == 0)
    }

    @Test("Two sightings over two days learn nothing")
    func tooFew() {
        var ledger = PairLedger()
        _ = record(&ledger, "kemma", "Gemma", day: 100)
        let found = record(&ledger, "kemma", "Gemma", day: 101)
        #expect(found.isEmpty)
    }

    @Test("A thousand edits in an hour learn at most the daily cap")
    func dailyCap() {
        var ledger = PairLedger()
        for index in 0..<1000 {
            _ = record(&ledger, "heard\(index)x", "Meant\(index)y", day: 100)
        }
        var learnt = 0
        for index in 0..<1000 {
            learnt += record(&ledger, "heard\(index)x", "Meant\(index)y", day: 101, times: 2).count
        }
        #expect(learnt == ConfusionPairs.maximumNewPairsPerDay)
    }

    @Test("A pair held back by the cap is learnt on a later day")
    func capDefers() {
        var ledger = PairLedger()
        let pairs = (0..<(ConfusionPairs.maximumNewPairsPerDay + 2)).map { ("heard\($0)x", "Meant\($0)y") }
        for pair in pairs { _ = record(&ledger, pair.0, pair.1, day: 100, times: 2) }
        var learnt = 0
        for pair in pairs { learnt += record(&ledger, pair.0, pair.1, day: 101).count }
        #expect(learnt == ConfusionPairs.maximumNewPairsPerDay)
        for pair in pairs { learnt += record(&ledger, pair.0, pair.1, day: 102).count }
        #expect(learnt == pairs.count)
    }

    @Test("A refused pair is never counted, and a refusal outlives a restart")
    func refusal() {
        var ledger = PairLedger()
        _ = record(&ledger, "kemma", "Gemma", day: 100)
        let cancelled = ledger.refuse(heard: "kemma", meant: "Gemma")
        #expect(cancelled.map(\.weight) == [-1])
        #expect(ledger.pendingCount == 0)
        var reloaded = PairLedger(refusing: ledger.refusals)
        var earlier: [ConfusionPairs.Pair] = []
        for day in 100...105 { earlier += record(&reloaded, "Kemma", "gemma", day: day, times: 3) }
        #expect(earlier.isEmpty)
        let lifted = reloaded.allow(heard: "kemma", meant: "Gemma")
        #expect(lifted)
        let before = record(&reloaded, "kemma", "Gemma", day: 110, times: 2)
        #expect(before.isEmpty)
        let after = record(&reloaded, "kemma", "Gemma", day: 111)
        #expect(after.count == 1)
    }

    @Test("Rows rebuild the tally after a restart and hold no text")
    func persistence() {
        var ledger = PairLedger(digest: { "h" + String($0.hashValue.magnitude) })
        var rows = ledger.record(heard: "kemma", meant: "Gemma", on: 100).rows
        rows += ledger.record(heard: "kemma", meant: "Gemma", on: 100).rows
        #expect(rows.allSatisfy { !$0.subject.contains("emma") })
        var reloaded = PairLedger(remembering: rows, digest: { "h" + String($0.hashValue.magnitude) })
        #expect(reloaded.pendingCount == 1)
        let third = reloaded.record(heard: "kemma", meant: "Gemma", on: 101)
        #expect(third.learnt != nil)
    }

    @Test("The daily cap survives a restart")
    func capPersists() {
        var ledger = PairLedger()
        var rows: [EvidenceRow] = []
        for index in 0..<ConfusionPairs.maximumNewPairsPerDay {
            rows += ledger.record(heard: "heard\(index)x", meant: "Meant\(index)y", on: 100).rows
            rows += ledger.record(heard: "heard\(index)x", meant: "Meant\(index)y", on: 101).rows
            rows += ledger.record(heard: "heard\(index)x", meant: "Meant\(index)y", on: 101).rows
        }
        var reloaded = PairLedger(remembering: rows)
        _ = record(&reloaded, "extra", "Pair", day: 100, times: 2)
        let found = record(&reloaded, "extra", "Pair", day: 101)
        #expect(found.count == 0)
    }

    @Test("A pair that changes nothing or is not Latin is not counted")
    func uncountable() {
        var ledger = PairLedger()
        let same = ledger.record(heard: "gemma", meant: "Gemma", on: 100)
        let empty = ledger.record(heard: "", meant: "Gemma", on: 100)
        let devanagari = ledger.record(heard: "kemma", meant: "जेम्मा", on: 100)
        #expect(same.rows.isEmpty && empty.rows.isEmpty && devanagari.rows.isEmpty)
        #expect(ledger.pendingCount == 0)
    }

    @Test("Pending pairs are bounded and clearing cancels every row")
    func bounded() {
        var ledger = PairLedger()
        for index in 0..<(PairLedger.maximumPending + 20) {
            _ = ledger.record(heard: "heard\(index)x", meant: "Meant\(index)y", on: 100)
        }
        #expect(ledger.pendingCount == PairLedger.maximumPending)
        let cancelled = ledger.clearPending()
        #expect(cancelled.count == PairLedger.maximumPending)
        #expect(ledger.pendingCount == 0)
    }
}
