extension Schema {
    /// Replaces each line a person forgot, once kept in full as its own successor, with its keyed digest.
    static func migrateForgottenToMarkers(_ database: Database) throws(PredictStoreError) {
        let forgotten = try database.rows(
            "SELECT id, surface_id, text FROM entry WHERE superseded_by = text AND count = 0", { _ in }
        ) { (Int64($0.integer(0)), Int64($0.integer(1)), $0.text(2)) }
        guard !forgotten.isEmpty else { return }
        let marker = try ForgottenMarker(database)
        for (id, surface, text) in forgotten {
            let digest = try marker(text)
            try database.run("INSERT OR IGNORE INTO forgotten (surface_id, marker) VALUES (?, ?)") {
                $0.bind(1, surface)
                $0.bind(2, digest)
            }
            try database.run("DELETE FROM entry WHERE id = ?") { $0.bind(1, id) }
        }
    }

    /// Adds indexed scope recency and seeds it from the newest entry in each surface.
    static func migrateToSurfaceRecency(_ database: Database) throws(PredictStoreError) {
        if !hasColumn("last_used", in: "surface", database) {
            try database.execute("ALTER TABLE surface ADD COLUMN last_used REAL NOT NULL DEFAULT 0")
        }
        try database.execute(
            "UPDATE surface SET last_used = COALESCE((SELECT MAX(last_used) FROM entry WHERE entry.surface_id = surface.id), 0)"
        )
    }

    /// Adds the mark for a line the person finished; no older line has one, since its ending was never kept.
    static func migrateToFinishedLines(_ database: Database) throws(PredictStoreError) {
        if !hasColumn("finished", in: "entry", database) {
            try database.execute("ALTER TABLE entry ADD COLUMN finished INTEGER NOT NULL DEFAULT 0")
        }
    }
}
