private let entryEvictionOrder = """
    CASE
      WHEN superseded_by IS NULL THEN 1
      WHEN length(superseded_by) > length(text)
        AND substr(lower(superseded_by), 1, length(text_lower)) = text_lower THEN 0
      ELSE 2
    END ASC, accepted ASC, count ASC, last_used ASC
    """

extension PredictStore {
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
