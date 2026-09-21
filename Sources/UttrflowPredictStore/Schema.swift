/// The tables the corpus lives in, and the one place their shape is written down.
enum Schema {
    /// What this build expects on disk; an older file is migrated to it and a newer one is refused.
    static let version = 4

    /// Everything a fresh database needs, in the order it must be created.
    static let statements = [
        "PRAGMA journal_mode = WAL",
        "PRAGMA synchronous = NORMAL",
        // Zeroes the cell a deleted row held, instead of leaving it until something overwrites it.
        "PRAGMA secure_delete = ON",
        "PRAGMA foreign_keys = ON",
        """
        CREATE TABLE IF NOT EXISTS schema_version (
          version INTEGER NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS surface (
          id        INTEGER PRIMARY KEY,
          bundle_id TEXT NOT NULL,
          role      TEXT NOT NULL,
          locator   TEXT NOT NULL DEFAULT '',
          scope     TEXT NOT NULL DEFAULT '',
          UNIQUE (bundle_id, role, locator, scope)
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS entry (
          id           INTEGER PRIMARY KEY,
          surface_id   INTEGER NOT NULL REFERENCES surface(id) ON DELETE CASCADE,
          text         TEXT NOT NULL,
          text_lower   TEXT NOT NULL DEFAULT '',
          count        INTEGER NOT NULL DEFAULT 1,
          accepted     INTEGER NOT NULL DEFAULT 0,
          rejected     INTEGER NOT NULL DEFAULT 0,
          self_sourced INTEGER NOT NULL DEFAULT 0,
          last_used    REAL NOT NULL,
          superseded_by TEXT,
          UNIQUE (surface_id, text)
        )
        """,
        // The scan every keystroke runs is over the lowercased text: case ignored, index kept.
        "CREATE INDEX IF NOT EXISTS entry_prefix ON entry (surface_id, text_lower)",
        // The lines most recently entered in a field are read newest first, which this index orders.
        "CREATE INDEX IF NOT EXISTS entry_recent ON entry (surface_id, last_used)",
        """
        CREATE TABLE IF NOT EXISTS succession (
          surface_id INTEGER NOT NULL REFERENCES surface(id) ON DELETE CASCADE,
          previous   TEXT NOT NULL,
          next       TEXT NOT NULL,
          count      INTEGER NOT NULL DEFAULT 1,
          PRIMARY KEY (surface_id, previous, next)
        )
        """,
    ]

    /// Brings an open database up to ``version``, creating it if it is empty.
    static func migrate(_ database: Database) throws(PredictStoreError) {
        for statement in statements { try database.execute(statement) }
        let found = try database.rows("SELECT version FROM schema_version LIMIT 1", { _ in }) {
            $0.integer(0)
        }
        guard let current = found.first else {
            try database.run("INSERT INTO schema_version (version) VALUES (?)") {
                $0.bind(1, Int64(version))
            }
            return
        }
        // A file from a newer build is not something this one can safely write to.
        guard current <= version else { throw .newerThanThisBuild(version: current) }
        if current < 2 { try migrateToLowercasedPrefix(database) }
        // Version 3 adds only `entry_recent`, which `statements` has already created above.
        if current < 4 {
            try database.transaction { () throws(PredictStoreError) in
                try migrateToCanonicalSpelling(database)
            }
            try relowercase(database)
        }
        if current < version {
            try database.run("UPDATE schema_version SET version = ?") { $0.bind(1, Int64(version)) }
        }
    }

    /// Adds the lowercased column an existing v1 file lacks, fills it, and moves the index onto it.
    private static func migrateToLowercasedPrefix(_ database: Database) throws(PredictStoreError) {
        if !hasColumn("text_lower", in: "entry", database) {
            try database.execute("ALTER TABLE entry ADD COLUMN text_lower TEXT NOT NULL DEFAULT ''")
        }
        try database.execute("DROP INDEX IF EXISTS entry_prefix")
        try database.execute("CREATE INDEX entry_prefix ON entry (surface_id, text_lower)")
    }

    /// Rewrites every key that differs from Swift's lowercasing, which SQLite's `lower` applies to ASCII only.
    private static func relowercase(_ database: Database) throws(PredictStoreError) {
        let rows = try database.rows("SELECT id, text, text_lower FROM entry", { _ in }) {
            (Int64($0.integer(0)), $0.text(1), $0.text(2))
        }
        for (id, text, stored) in rows where text.lowercased() != stored {
            try database.run("UPDATE entry SET text_lower = ? WHERE id = ?") {
                $0.bind(1, text.lowercased())
                $0.bind(2, id)
            }
        }
    }

    /// Rewrites every stored line in its canonical encoding, folding the rows that turn out to be one line into one.
    private static func migrateToCanonicalSpelling(_ database: Database) throws(PredictStoreError) {
        let entries = try database.rows(
            "SELECT id, surface_id, text, count, accepted, rejected, self_sourced, last_used FROM entry",
            { _ in }
        ) { row in
            (
                id: Int64(row.integer(0)), surface: Int64(row.integer(1)), text: row.text(2),
                count: Int64(row.integer(3)),
                accepted: Int64(row.integer(4)), rejected: Int64(row.integer(5)),
                selfSourced: Int64(row.integer(6)),
                lastUsed: row.double(7)
            )
        }
        for entry in entries where !Spelling.isCanonical(entry.text) {
            let text = Spelling.canonical(entry.text)
            let merged = try database.run(
                """
                UPDATE entry SET count = count + ?, accepted = accepted + ?, rejected = rejected + ?,
                  self_sourced = self_sourced + ?, last_used = MAX(last_used, ?)
                WHERE surface_id = ? AND text = ?
                """,
                {
                    $0.bind(1, entry.count)
                    $0.bind(2, entry.accepted)
                    $0.bind(3, entry.rejected)
                    $0.bind(4, entry.selfSourced)
                    $0.bind(5, entry.lastUsed)
                    $0.bind(6, entry.surface)
                    $0.bind(7, text)
                })
            if merged > 0 {
                try database.run("DELETE FROM entry WHERE id = ?") { $0.bind(1, entry.id) }
            } else {
                try database.run("UPDATE entry SET text = ?, text_lower = ? WHERE id = ?") {
                    $0.bind(1, text)
                    $0.bind(2, text.lowercased())
                    $0.bind(3, entry.id)
                }
            }
        }
        let replacements = try database.rows(
            "SELECT DISTINCT superseded_by FROM entry WHERE superseded_by IS NOT NULL", { _ in }
        ) { $0.text(0) }
        for replacement in replacements where !Spelling.isCanonical(replacement) {
            try database.run("UPDATE entry SET superseded_by = ? WHERE superseded_by = ?") {
                $0.bind(1, Spelling.canonical(replacement))
                $0.bind(2, replacement)
            }
        }
        let successions = try database.rows(
            "SELECT surface_id, previous, next, count FROM succession", { _ in }
        ) {
            (
                surface: Int64($0.integer(0)), previous: $0.text(1), next: $0.text(2),
                count: Int64($0.integer(3))
            )
        }
        for pair in successions where !Spelling.isCanonical(pair.previous) || !Spelling.isCanonical(pair.next)
        {
            try database.run("DELETE FROM succession WHERE surface_id = ? AND previous = ? AND next = ?") {
                $0.bind(1, pair.surface)
                $0.bind(2, pair.previous)
                $0.bind(3, pair.next)
            }
            try database.run(
                """
                INSERT INTO succession (surface_id, previous, next, count) VALUES (?, ?, ?, ?)
                ON CONFLICT (surface_id, previous, next) DO UPDATE SET count = count + excluded.count
                """,
                {
                    $0.bind(1, pair.surface)
                    $0.bind(2, Spelling.canonical(pair.previous))
                    $0.bind(3, Spelling.canonical(pair.next))
                    $0.bind(4, pair.count)
                })
        }
    }

    /// Whether a table already has a column, so a migration does not add one twice.
    private static func hasColumn(
        _ column: String, in table: String, _ database: Database
    ) -> Bool {
        let names = (try? database.rows("PRAGMA table_info(\(table))", { _ in }) { $0.text(1) }) ?? []
        return names.contains(column)
    }
}
