// Tests that applications nobody confirmed leave an entry's rank and standing unchanged.

import Foundation
import Testing
import UttrflowCore

@testable import UttrflowDictionary

@Suite("Accepted-use rank")
struct AcceptedRankTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a hundred unconfirmed applications leave netUses and value at their first-application level")
    func applicationsAloneRaiseNothing() {
        let first = DictionaryEntry(
            word: "Kubernets", origin: .added, firstSeen: now, timesUsed: 1, timesAccepted: 0)
        let hundred = DictionaryEntry(
            word: "Kubernets", origin: .added, firstSeen: now, timesUsed: 100, timesAccepted: 0)
        #expect(hundred.netUses == first.netUses)
        let code = WordSound(of: "Kubernets")
        #expect(
            WorkingSet.value(of: hundred, sounding: code, now: now, wanted: [])
                == WorkingSet.value(of: first, sounding: code, now: now, wanted: []))
    }

    @Test("accepted uses raise value, and never exceed uses")
    func acceptedUsesRaiseValue() throws {
        let code = WordSound(of: "Kubernetes")
        let low = DictionaryEntry(
            word: "Kubernetes", origin: .added, firstSeen: now, timesUsed: 5, timesAccepted: 0)
        let high = DictionaryEntry(
            word: "Kubernetes", origin: .added, firstSeen: now, timesUsed: 5, timesAccepted: 5)
        #expect(
            WorkingSet.value(of: high, sounding: code, now: now, wanted: [])
                > WorkingSet.value(of: low, sounding: code, now: now, wanted: []))
        #expect(
            DictionaryEntry(word: "x", origin: .added, firstSeen: now, timesUsed: 1, timesAccepted: 9)
                .timesAccepted == 1)
    }
}
