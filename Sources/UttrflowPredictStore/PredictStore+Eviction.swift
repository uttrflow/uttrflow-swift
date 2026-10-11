import UttrflowCore
import UttrflowPredict

public import struct Foundation.Date

private let entryEvictionOrder = """
    CASE
      WHEN superseded_by IS NULL THEN 1
      WHEN length(superseded_by) > length(text)
        AND substr(lower(superseded_by), 1, length(text_lower)) = text_lower THEN 0
      ELSE 2
    END ASC, accepted ASC, count ASC, last_used ASC
    """

extension PredictStore {
    /// Keeps the whole corpus within its cap, dropping the weakest entries anywhere but the one just written.
    func evictWeakestAcrossStore(
        protectingSurface id: Int64, text: String
    ) throws(PredictStoreError) {
        let held = try database.rows("SELECT COUNT(*) FROM entry", { _ in }) { $0.integer(0) }
        guard let held = held.first, held > Self.entriesPerStore else { return }
        try database.run(
            """
            DELETE FROM entry WHERE id IN (
              SELECT id FROM entry WHERE NOT (surface_id = ? AND text = ?)
              ORDER BY \(entryEvictionOrder) LIMIT ?
            )
            """,
            {
                $0.bind(1, id)
                $0.bind(2, text)
                $0.bind(3, Int64(held - Self.entriesPerStore))
            })
    }

    /// Removes entries aged below `PredictionEngine.supportFloor`; refused lines and untrusted stamps stay.
    @discardableResult
    public func expireStale(now: Date) throws(PredictStoreError) -> Int {
        let window = RetentionWindow(span: 0, now: now)
        let aged = try database.rows(
            """
            SELECT id, count, self_sourced, last_used FROM entry
            WHERE last_used > 0 AND superseded_by IS NULL AND rejected = 0
            """, { _ in }
        ) {
            (
                id: Int64($0.integer(0)), count: $0.integer(1), selfSourced: $0.integer(2),
                lastUsed: $0.double(3)
            )
        }
        let due = aged.filter { row in
            let stamp = Date(timeIntervalSince1970: row.lastUsed)
            let evidence = Entry(
                text: "", count: row.count, selfSourced: row.selfSourced, lastUsed: stamp)
            let score = Frecency.score(Candidate(text: "", source: .personal, evidence: evidence), now: now)
            return score < PredictionEngine.supportFloor && window.mayDelete(stamp)
        }
        guard !due.isEmpty else { return 0 }
        try database.transaction { () throws(PredictStoreError) in
            for row in due {
                try database.run("DELETE FROM entry WHERE id = ?") { $0.bind(1, row.id) }
            }
        }
        return due.count
    }

    /// Keeps a surface within its cap, protecting the entry this write just inserted.
    func evictWeakest(
        surfaceIdentifier id: Int64, protecting text: String? = nil,
        succession: (previous: String, next: String)? = nil
    ) throws(PredictStoreError) {
        try evictWeakestSuccessions(surfaceIdentifier: id, protecting: succession)
        let held = try database.rows(
            "SELECT COUNT(*) FROM entry WHERE surface_id = ?", { $0.bind(1, id) }
        ) { $0.integer(0) }
        guard let held = held.first, held > Self.entriesPerSurface else { return }
        try database.run(
            """
            DELETE FROM entry WHERE id IN (
              SELECT id FROM entry WHERE surface_id = ? AND (? IS NULL OR text != ?)
              ORDER BY \(entryEvictionOrder) LIMIT ?
            )
            """,
            {
                $0.bind(1, id)
                $0.bind(2, text)
                $0.bind(3, text)
                $0.bind(4, Int64(held - Self.entriesPerSurface))
            })
    }

    /// Keeps a surface's successions within the entry cap, dropping the least followed and then the oldest.
    private func evictWeakestSuccessions(
        surfaceIdentifier id: Int64, protecting succession: (previous: String, next: String)?
    ) throws(PredictStoreError) {
        let held = try database.rows(
            "SELECT COUNT(*) FROM succession WHERE surface_id = ?", { $0.bind(1, id) }
        ) { $0.integer(0) }
        guard let held = held.first, held > Self.entriesPerSurface else { return }
        let previous = succession?.previous
        let next = succession?.next
        try database.run(
            """
            DELETE FROM succession WHERE rowid IN (
              SELECT rowid FROM succession WHERE surface_id = ?
                AND (? IS NULL OR previous != ? OR next != ?)
              ORDER BY count ASC, rowid ASC LIMIT ?
            )
            """,
            {
                $0.bind(1, id)
                $0.bind(2, previous)
                $0.bind(3, previous)
                $0.bind(4, next)
                $0.bind(5, Int64(held - Self.entriesPerSurface))
            })
    }
}
