// Tests for the last-use dates and the not-used-lately list projected from the ledger.

import Foundation
import Testing
import UttrflowCore

@testable import UttrflowDictionary

@Suite("When a word last appeared, projected from the evidence ledger")
struct WordRecencyTests {
    private let today = EvidenceRow.day(of: epoch)

    private func use(_ id: UUID, daysAgo: Int) -> EvidenceRow {
        EvidenceRow(kind: .use, subject: id.uuidString, day: today - daysAgo, provenance: .dictation)
    }

    private func stale(_ entries: [DictionaryEntry], _ rows: [EvidenceRow], window: Int = 365) -> Set<UUID> {
        WordRecency(entries: entries, evidence: rows, now: epoch, evidenceDays: window).stale
    }

    @Test("Lists exactly the learned and observed words past 90 days and never an added or shipped one")
    func listsInferredWordsOnly() {
        let rows = (0..<4).map { _ in UUID() }
        let words = [
            word("Alpha", from: .learned, used: 1, daysAgo: 400, id: rows[0]),
            word("Bravo", from: .observed, used: 1, daysAgo: 400, id: rows[1]),
            word("Charlie", from: .added, used: 1, daysAgo: 400, id: rows[2]),
            word("Delta", from: .shipped, used: 1, daysAgo: 400, id: rows[3]),
        ]
        let evidence = rows.map { use($0, daysAgo: 120) }
        #expect(stale(words, evidence) == [rows[0], rows[1]])
    }

    @Test("A use 89 days ago is not stale and one 90 days ago is")
    func boundary() {
        let fresh = word("Alpha", used: 1, daysAgo: 400)
        let old = word("Bravo", used: 1, daysAgo: 400)
        #expect(stale([fresh, old], [use(fresh.id, daysAgo: 89), use(old.id, daysAgo: 90)]) == [old.id])
    }

    @Test("A word first seen long ago and used yesterday is not stale")
    func recentUseWins() {
        let entry = word("Alpha", used: 5, daysAgo: 2000)
        #expect(stale([entry], [use(entry.id, daysAgo: 1), use(entry.id, daysAgo: 800)]).isEmpty)
    }

    @Test("A word never used is stale from the day it was first seen")
    func neverUsed() {
        let old = word("Alpha", daysAgo: 91)
        let young = word("Bravo", daysAgo: 10)
        #expect(stale([old, young], []) == [old.id])
    }

    @Test("A used word with no row is stale only when the ledger window reaches back 90 days")
    func windowBoundsTheClaim() {
        let entry = word("Alpha", used: 3, daysAgo: 400)
        #expect(stale([entry], [], window: 30).isEmpty)
        #expect(stale([entry], [], window: 90) == [entry.id])
    }

    @Test("The last use is the newest use row's day, and a word with none has no date")
    func lastUsedDates() {
        let used = word("Alpha", used: 2, daysAgo: 400)
        let unused = word("Bravo", daysAgo: 400)
        let recency = WordRecency(
            entries: [used, unused], evidence: [use(used.id, daysAgo: 40), use(used.id, daysAgo: 3)],
            now: epoch, evidenceDays: 365)
        #expect(recency.lastUsed[used.id] == Date(timeIntervalSince1970: Double(today - 3) * 86_400))
        #expect(recency.lastUsed[unused.id] == nil)
    }

    @Test("Computing staleness changes no entry, so nothing is removed by the list")
    func removesNothing() {
        let entries = [word("Alpha", used: 1, daysAgo: 400), word("Bravo", from: .added, daysAgo: 400)]
        let before = entries
        _ = stale(entries, [])
        #expect(entries == before)
    }
}
