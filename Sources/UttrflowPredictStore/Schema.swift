/// The tables the corpus lives in, and the one place their shape is written down.
enum Schema {
    /// What this build expects on disk; an older file is migrated to it and a newer one is refused.
    static let version = 3

    /// Everything a fresh database needs, in the order it must be created.
    static let statements = [
        "PRAGMA journal_mode = WAL",
        "PRAGMA synchronous = NORMAL",
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
        // The range scan every keystroke runs is over the lowercased text, so matching ignores case but keeps the index.
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
        if current < version {
            try database.run("UPDATE schema_version SET version = ?") { $0.bind(1, Int64(version)) }
        }
    }

    /// Adds the lowercased column an existing v1 file lacks, fills it, and moves the index onto it.
    private static func migrateToLowercasedPrefix(_ database: Database) throws(PredictStoreError) {
        if !hasColumn("text_lower", in: "entry", database) {
            try database.execute("ALTER TABLE entry ADD COLUMN text_lower TEXT NOT NULL DEFAULT ''")
        }
        try database.execute("UPDATE entry SET text_lower = lower(text)")
        try database.execute("DROP INDEX IF EXISTS entry_prefix")
        try database.execute("CREATE INDEX entry_prefix ON entry (surface_id, text_lower)")
    }

    /// Whether a table already has a column, so a migration does not add one twice.
    private static func hasColumn(
        _ column: String, in table: String, _ database: Database
    ) -> Bool {
        let names = (try? database.rows("PRAGMA table_info(\(table))", { _ in }) { $0.text(1) }) ?? []
        return names.contains(column)
    }
}
