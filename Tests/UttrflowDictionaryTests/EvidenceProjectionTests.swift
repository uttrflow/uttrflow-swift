// Prototype evidence ledger, checked against today's counters. See `Docs/learned-state.md`.

import Foundation
import Testing

@testable import UttrflowDictionary

/// One observed fact about one subject, as `Docs/learned-state.md` defines the row.
private struct EvidenceRow: Equatable {
    enum Kind: Equatable { case use, revert, restore }
    let kind: Kind
    let subject: UUID
    let weight: Int
    let day: Int
}

/// The prototype ledger: rows in, projections out, nothing stored as a counter.
private struct EvidenceLedger {
    var rows: [EvidenceRow] = []

    /// The rows one migrated dictionary entry becomes, a zero count writing no row.
    static func migrating(_ entry: DictionaryEntry, on day: Int) -> [EvidenceRow] {
        [
            EvidenceRow(kind: .use, subject: entry.id, weight: entry.timesUsed, day: day),
            EvidenceRow(kind: .revert, subject: entry.id, weight: entry.timesReverted, day: day),
        ].filter { $0.weight != 0 }
    }

    /// Uses counted for a subject.
    func used(_ subject: UUID) -> Int {
        rows.filter { $0.kind == .use && $0.subject == subject }.reduce(0) { $0 + $1.weight }
    }

    /// Undos counted for a subject, ignoring those at or before its latest restore.
    func reverted(_ subject: UUID) -> Int {
        let restoredAt = rows.lastIndex { $0.kind == .restore && $0.subject == subject }
        return rows.indices.filter { index in
            rows[index].kind == .revert && rows[index].subject == subject
                && restoredAt.map { index > $0 } ?? true
        }.reduce(0) { $0 + rows[$1].weight }
    }

    /// The projection that replaces `DictionaryEntry.netUses`.
    func netUses(_ subject: UUID) -> Int { used(subject) - reverted(subject) }

    /// The projection that replaces `DictionaryEntry.isTrustworthy`.
    func isTrustworthy(_ subject: UUID) -> Bool {
        let uses = used(subject)
        guard uses >= 3 else { return true }
        return Double(reverted(subject)) / Double(uses) < 0.5
    }

    /// Folds each run of rows of one kind and subject between restores into one row.
    func compacted() -> EvidenceLedger {
        var folded: [EvidenceRow] = []
        for row in rows {
            if row.kind != .restore, let last = folded.lastIndex(where: { $0.subject == row.subject }),
                folded[last].kind == row.kind
            {
                folded[last] = EvidenceRow(
                    kind: row.kind, subject: row.subject, weight: folded[last].weight + row.weight,
                    day: max(folded[last].day, row.day))
            } else {
                folded.append(row)
            }
        }
        return EvidenceLedger(rows: folded)
    }
}

@Suite("A ledger of evidence reproduces today's dictionary counters")
struct EvidenceProjectionTests {
    /// Migrating counters into rows must not move a single word in or out of the working set.
    @Test("migrated counters project the same net uses and trust as the entry")
    func migrationPreservesProjections() {
        for used in 0...12 {
            for reverted in 0...12 {
                let entry = word("Uttrflow", used: used, reverted: reverted)
                let ledger = EvidenceLedger(rows: EvidenceLedger.migrating(entry, on: 0))
                #expect(ledger.netUses(entry.id) == entry.netUses, "used \(used), reverted \(reverted)")
                #expect(
                    ledger.isTrustworthy(entry.id) == entry.isTrustworthy,
                    "used \(used), reverted \(reverted)")
            }
        }
    }

    /// The store and the ledger see the same history and must agree after every step, restore included.
    @Test("replaying uses, undos and a restore agrees with the store at every step")
    func replayAgreesWithStore() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        let entry = word("kubectl", from: .added)
        try await store.add(entry)

        let steps: [EvidenceRow.Kind] = [
            .use, .use, .revert, .use, .revert, .revert, .restore, .use, .revert,
        ]
        var ledger = EvidenceLedger()
        for (day, step) in steps.enumerated() {
            let stored: DictionaryEntry?
            switch step {
            case .use: stored = try await store.recordUse(of: entry.id)
            case .revert: stored = try await store.recordRevert(of: entry.id)
            case .restore: stored = try await store.restore(entry.id)
            }
            ledger.rows.append(EvidenceRow(kind: step, subject: entry.id, weight: 1, day: day))
            let current = try #require(stored)
            #expect(ledger.netUses(entry.id) == current.netUses, "after step \(day)")
            #expect(ledger.isTrustworthy(entry.id) == current.isTrustworthy, "after step \(day)")
            #expect(ledger.compacted().netUses(entry.id) == current.netUses, "compacted, after step \(day)")
            #expect(
                ledger.compacted().isTrustworthy(entry.id) == current.isTrustworthy, "compacted, step \(day)")
        }
    }
}
