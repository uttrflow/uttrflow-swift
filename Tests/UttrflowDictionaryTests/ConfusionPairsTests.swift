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

    /// Allowing a vetoed pair lifts every undo up to that day; a later undo vetoes it again.
    @Test("Allow lifts earlier undos only")
    func allowLiftsEarlierUndos() {
        let allow = ConfusionPairs.allowing(heard: "nickel", meant: "Nikhil", day: 2)
        let allowed = undone(days: [1, 2]) + allow
        #expect(ConfusionPairs.project(allowed).isEmpty)
        #expect(ConfusionPairs.project(allowed + undone(days: [3])) == [key: .vetoed])
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

    private func retried(days: [Int]) -> [EvidenceRow] {
        days.flatMap { day in
            ConfusionPairs.retrying(
                [ConfusionPairs.Pair(heard: "nickel", meant: "Nikhil")], heard: "ask nickel about it",
                retryHeard: "ask Nikhil about it", retryWrote: "Ask Nikhel about it.", day: day)
        }
    }

    /// One re-dictation changes nothing; re-dictations on two separate days veto a pair nobody kept.
    @Test("A single re-dictation never vetoes on its own")
    func singleRetryInert() {
        #expect(retried(days: [1]).count == 1)
        #expect(ConfusionPairs.project(retried(days: [1])).isEmpty)
        #expect(ConfusionPairs.project(retried(days: [1, 1, 1])).isEmpty)
        #expect(ConfusionPairs.project(retried(days: [1, 2])) == [key: .vetoed])
    }

    /// However many days a pair is respoken, re-dictations add at most one undone day, so one kept day holds them.
    @Test("Re-dictations are capped below one kept day")
    func retriesCapped() {
        #expect(ConfusionPairs.project(kept(days: [1]) + retried(days: Array(2...30))).isEmpty)
        #expect(ConfusionPairs.project(undone(days: [1]) + retried(days: [1, 2])) == [key: .vetoed])
    }

    /// Allowing a pair lifts the re-dictations up to that day, as it lifts undos.
    @Test("Allow lifts earlier re-dictations")
    func allowLiftsRetries() {
        let allow = ConfusionPairs.allowing(heard: "nickel", meant: "Nikhil", day: 2)
        #expect(ConfusionPairs.project(retried(days: [1, 2]) + allow).isEmpty)
    }

    /// Only a respeaking that drops the written word counts: different words, or the word kept, record nothing.
    @Test("A re-dictation is read only from similar words that drop the correction")
    func retryDetection() {
        let pair = ConfusionPairs.Pair(heard: "nickel", meant: "Nikhil")
        let respoken = { (retryHeard: String, retryWrote: String) in
            ConfusionPairs.retrying(
                [pair], heard: "ask nickel about the meeting", retryHeard: retryHeard, retryWrote: retryWrote,
                day: 1)
        }
        #expect(
            respoken("ask Nikhil about the meeting", "Ask Nikhel about the meeting.") == [
                EvidenceRow(kind: .pairRetried, subject: key, day: 1, provenance: .dictation)
            ])
        #expect(respoken("buy milk on the way home", "Buy milk on the way home.").isEmpty)
        #expect(respoken("ask Nikhil about the meeting", "Ask Nikhil about the meeting.").isEmpty)
        #expect(respoken("", "").isEmpty)
    }

    /// One re-dictation writes against at most a capped number of pairs.
    @Test("One re-dictation writes a capped number of rows")
    func retryRowsCapped() {
        let pairs = ["one", "two", "three", "four", "five"].map {
            ConfusionPairs.Pair(heard: $0, meant: $0 + "x")
        }
        let rows = ConfusionPairs.retrying(
            pairs, heard: "one two three four five", retryHeard: "one two three four five",
            retryWrote: "one two three four five", day: 1)
        #expect(rows.count == ConfusionPairs.retriedPairsPerDictation)
    }
}
