// Tests for heard-to-meant pairs projected from evidence rows.

import Testing
import UttrflowCore

@testable import UttrflowDictionary

@Suite("Heard-to-meant pairs")
struct ConfusionPairsTests {
    private let key = ConfusionPairs.key(heard: "nickel", meant: "Nikhil")

    private func kept(days: [Int]) -> [EvidenceRow] {
        days.flatMap { ConfusionPairs.confirming(heard: "nickel", meant: "Nikhil", day: $0) }
    }

    private func undone(days: [Int]) -> [EvidenceRow] {
        days.flatMap { ConfusionPairs.vetoing(heard: "nickel", meant: "Nikhil", day: $0) }
    }

    /// One undo of "nickel" to "Nikhil" vetoes that pair and no other.
    @Test("One undo vetoes the pair only")
    func undoVetoesPairOnly() {
        let rows = undone(days: [1]) + ConfusionPairs.confirming(heard: "pickle", meant: "Nikhil", day: 1)
        #expect(ConfusionPairs.project(rows) == [key: .vetoed])
    }

    /// A pair kept on three separate days becomes a feature; fewer days, or three on one day, do not.
    @Test("Three separate days confirm a pair")
    func threeDaysConfirm() {
        #expect(ConfusionPairs.project(kept(days: [1, 2, 3])) == [key: .confirmed])
        #expect(ConfusionPairs.project(kept(days: [1, 2])).isEmpty)
        #expect(ConfusionPairs.project(kept(days: [5, 5, 5])).isEmpty)
    }

    /// Equal days kept and undone leave the pair inert.
    @Test("Equal confirmed and vetoed days are inert")
    func equalDaysInert() {
        #expect(ConfusionPairs.project(kept(days: [1, 2, 3]) + undone(days: [4, 5, 6])).isEmpty)
    }

    /// The heard side is closed up, so spacing and case in what was heard name one pair.
    @Test("Heard words are closed up into one key")
    func heardClosedUp() {
        #expect(ConfusionPairs.key(heard: "Nick El", meant: "Nikhil") == key)
    }

    /// A pair that changes nothing, or has an empty side, writes no row.
    @Test("A pair that records no confusion writes nothing")
    func emptyPairsRefused() {
        #expect(ConfusionPairs.confirming(heard: "nikhil", meant: "Nikhil", day: 1).isEmpty)
        #expect(ConfusionPairs.confirming(heard: "", meant: "Nikhil", day: 1).isEmpty)
        #expect(ConfusionPairs.vetoing(heard: "nickel", meant: "", day: 1).isEmpty)
    }
}
