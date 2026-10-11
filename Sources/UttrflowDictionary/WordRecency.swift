// When each dictionary word last appeared, projected from the evidence ledger and never stored. See `Docs/learned-state.md`.

public import UttrflowCore
public import struct Foundation.Date
public import struct Foundation.UUID

/// The last day each word was used and which inferred words have gone unused long enough to list as stale.
public struct WordRecency: Sendable, Equatable {
    /// The days without a use after which a learned or observed word is listed as not used lately.
    public static let staleAfterDays = 90

    /// No evidence read, so no word has a last use and none is stale.
    public static let none = WordRecency(lastUsed: [:], stale: [])

    /// The first moment of the newest day each word has a `use` row on.
    public let lastUsed: [UUID: Date]
    /// The learned or observed words with no use in `staleAfterDays`; an added or shipped word is never in it.
    public let stale: Set<UUID>

    init(lastUsed: [UUID: Date], stale: Set<UUID>) {
        self.lastUsed = lastUsed
        self.stale = stale
    }

    /// Reads the ledger inside History's window; without a ledger only a word with zero uses is proven unused.
    public static func read(
        from ledger: EvidenceLedgerStore?, entries: [DictionaryEntry], retentionDays: Int, now: Date = Date()
    ) async -> WordRecency {
        let rows = await ledger?.rows(keeping: RetentionWindow(days: retentionDays, now: now)) ?? []
        return WordRecency(
            entries: entries, evidence: rows, now: now, evidenceDays: ledger == nil ? 0 : retentionDays)
    }

    /// Reads the ledger rows held for `evidenceDays` back from `now`; a window shorter than the stale span proves no word unused.
    public init(entries: [DictionaryEntry], evidence: [EvidenceRow], now: Date, evidenceDays: Int) {
        let lastDays = PersonaProjection.lastUse(in: evidence)
        let today = EvidenceRow.day(of: now)
        var stale: Set<UUID> = []
        for entry in entries where entry.origin == .learned || entry.origin == .observed {
            let added = EvidenceRow.day(of: entry.firstSeen)
            let idleDays: Int?
            if let last = lastDays[entry.id] {
                idleDays = today - last
            } else if entry.timesUsed == 0 {
                idleDays = today - added
            } else {
                // Used before, but not inside the rows kept: proven unused for the window and the word's age only.
                idleDays = min(evidenceDays, today - added)
            }
            if let idleDays, idleDays >= Self.staleAfterDays { stale.insert(entry.id) }
        }
        self.init(
            lastUsed: lastDays.mapValues { Date(timeIntervalSince1970: Double($0) * 86_400) },
            stale: stale)
    }
}
