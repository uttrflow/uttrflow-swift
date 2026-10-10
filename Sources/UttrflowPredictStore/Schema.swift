import UttrflowCore

/// The tables the corpus lives in, and the one place their shape is written down.
enum Schema {
    /// What this build expects on disk; an older file is migrated to it and a newer one is refused.
    static let version = 8

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
          last_used REAL NOT NULL DEFAULT 0,
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
          finished     INTEGER NOT NULL DEFAULT 0,
          last_used    REAL NOT NULL,
          superseded_by TEXT,
          UNIQUE (surface_id, text)
        )
        """,
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
        // A forgotten line, kept only as its keyed digest so it stays forgotten without being kept.
        """
        CREATE TABLE IF NOT EXISTS forgotten (
          surface_id INTEGER NOT NULL REFERENCES surface(id) ON DELETE CASCADE,
          marker     TEXT NOT NULL,
          PRIMARY KEY (surface_id, marker)
        )
        """,
        // The secret those digests are keyed with when the corpus has no shared encryption key.
        """
        CREATE TABLE IF NOT EXISTS install_secret (
          secret TEXT NOT NULL
        )
        """,
        // The version of each refusal rule the stored lines were last swept with.
        """
        CREATE TABLE IF NOT EXISTS sweep (
          name    TEXT PRIMARY KEY,
          version INTEGER NOT NULL
        )
        """,
    ]

    /// Brings an open database up to ``version``, creating it if it is empty.
    static func migrate(_ database: Database) throws(PredictStoreError) {
        let schemaVersionBefore = try database.rows("PRAGMA schema_version", { _ in }) {
            $0.integer(0)
        }.first
        let hasVersionTable =
            try database.rows(
                "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'schema_version' LIMIT 1",
                { _ in }
            ) { _ in true }.first == true
        let found =
            hasVersionTable
            ? try database.rows("SELECT version FROM schema_version LIMIT 1", { _ in }) { $0.integer(0) }
            : []
        if let current = found.first {
            guard current <= version else { throw .newerThanThisBuild(version: current) }
        }
        for statement in statements { try database.execute(statement) }
        if let current = found.first {
            if current < 2 { try migrateToLowercasedPrefix(database) }
            // Version 3 adds only `entry_recent`, which `statements` has already created above.
            if current < 4 {
                try database.transaction { () throws(PredictStoreError) in
                    try migrateToCanonicalSpelling(database)
                }
                try relowercase(database)
            }
            if current < 5 {
                try database.transaction { () throws(PredictStoreError) in
                    try migrateToApplicationKeys(database)
                }
            }
            if current < 6 {
                try database.transaction { () throws(PredictStoreError) in
                    try migrateToSurfaceRecency(database)
                }
            }
            if current < 7 {
                try database.transaction { () throws(PredictStoreError) in
                    try migrateForgottenToMarkers(database)
                }
            }
            if current < 8 { try migrateToFinishedLines(database) }
            if current < version {
                try database.run("UPDATE schema_version SET version = ?") { $0.bind(1, Int64(version)) }
            }
        } else {
            try database.run("INSERT INTO schema_version (version) VALUES (?)") {
                $0.bind(1, Int64(version))
            }
        }
        // The prefix scan depends on a column older files gain during migration.
        try database.execute("CREATE INDEX IF NOT EXISTS entry_prefix ON entry (surface_id, text_lower)")
        // The recency index is created after migrations add its indexed column.
        try database.execute(
            "CREATE INDEX IF NOT EXISTS surface_recent ON surface (bundle_id, role, locator, last_used)")
        let schemaVersionAfter = try database.rows("PRAGMA schema_version", { _ in }) {
            $0.integer(0)
        }.first
        if schemaVersionBefore != schemaVersionAfter { try database.markSchemaChanged() }
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

    /// Folds surfaces that macOS named with different bundle-identifier casing into one application key.
    private static func migrateToApplicationKeys(_ database: Database) throws(PredictStoreError) {
        let surfaces = try database.rows(
            "SELECT id, bundle_id, role, locator, scope FROM surface ORDER BY id", { _ in }
        ) {
            (
                id: Int64($0.integer(0)), bundle: $0.text(1), role: $0.text(2), locator: $0.text(3),
                scope: $0.text(4)
            )
        }
        for surface in surfaces {
            let key = ApplicationKey.of(surface.bundle)
            guard key != surface.bundle else { continue }
            guard
                let target = try identifier(
                    bundleIdentifier: key, role: surface.role, locator: surface.locator,
                    scope: surface.scope, excluding: surface.id, database)
            else {
                try database.run("UPDATE surface SET bundle_id = ? WHERE id = ?") {
                    $0.bind(1, key)
                    $0.bind(2, surface.id)
                }
                continue
            }
            try moveEntries(from: surface.id, to: target, database)
            try moveSuccessions(from: surface.id, to: target, database)
            try database.run("DELETE FROM surface WHERE id = ?") { $0.bind(1, surface.id) }
        }
    }

    /// Finds the surface row for a field, ignoring the row currently being rewritten.
    private static func identifier(
        bundleIdentifier: String, role: String, locator: String, scope: String, excluding id: Int64,
        _ database: Database
    ) throws(PredictStoreError) -> Int64? {
        try database.rows(
            """
            SELECT id FROM surface
            WHERE bundle_id = ? AND role = ? AND locator = ? AND scope = ? AND id != ?
            """,
            {
                $0.bind(1, bundleIdentifier)
                $0.bind(2, role)
                $0.bind(3, locator)
                $0.bind(4, scope)
                $0.bind(5, id)
            }
        ) { Int64($0.integer(0)) }.first
    }

    /// Moves entries to another surface, merging duplicate texts instead of dropping either history.
    private static func moveEntries(
        from source: Int64, to target: Int64, _ database: Database
    ) throws(PredictStoreError) {
        let entries = try database.rows(
            """
            SELECT id, text, text_lower, count, accepted, rejected, self_sourced, last_used, superseded_by
            FROM entry WHERE surface_id = ?
            """,
            { $0.bind(1, source) }
        ) {
            (
                id: Int64($0.integer(0)), text: $0.text(1), textLower: $0.text(2),
                count: Int64($0.integer(3)), accepted: Int64($0.integer(4)),
                rejected: Int64($0.integer(5)), selfSourced: Int64($0.integer(6)),
                lastUsed: $0.double(7), supersededBy: $0.optionalText(8)
            )
        }
        for entry in entries {
            let merged = try database.run(
                """
                UPDATE entry SET count = count + ?, accepted = accepted + ?, rejected = rejected + ?,
                  self_sourced = self_sourced + ?, last_used = MAX(last_used, ?),
                  superseded_by = COALESCE(superseded_by, ?)
                WHERE surface_id = ? AND text = ?
                """,
                {
                    $0.bind(1, entry.count)
                    $0.bind(2, entry.accepted)
                    $0.bind(3, entry.rejected)
                    $0.bind(4, entry.selfSourced)
                    $0.bind(5, entry.lastUsed)
                    if let supersededBy = entry.supersededBy { $0.bind(6, supersededBy) }
                    $0.bind(7, target)
                    $0.bind(8, entry.text)
                })
            if merged > 0 {
                try database.run("DELETE FROM entry WHERE id = ?") { $0.bind(1, entry.id) }
            } else {
                try database.run("UPDATE entry SET surface_id = ? WHERE id = ?") {
                    $0.bind(1, target)
                    $0.bind(2, entry.id)
                }
            }
        }
    }

    /// Moves successor pairs to another surface, adding counts where the same pair already exists.
    private static func moveSuccessions(
        from source: Int64, to target: Int64, _ database: Database
    ) throws(PredictStoreError) {
        let pairs = try database.rows(
            "SELECT previous, next, count FROM succession WHERE surface_id = ?", { $0.bind(1, source) }
        ) { (previous: $0.text(0), next: $0.text(1), count: Int64($0.integer(2))) }
        for pair in pairs {
            try database.run(
                """
                INSERT INTO succession (surface_id, previous, next, count) VALUES (?, ?, ?, ?)
                ON CONFLICT (surface_id, previous, next) DO UPDATE SET count = count + excluded.count
                """,
                {
                    $0.bind(1, target)
                    $0.bind(2, pair.previous)
                    $0.bind(3, pair.next)
                    $0.bind(4, pair.count)
                })
        }
    }

    /// Whether a table already has a column, so a migration does not add one twice.
    static func hasColumn(
        _ column: String, in table: String, _ database: Database
    ) -> Bool {
        let names = (try? database.rows("PRAGMA table_info(\(table))", { _ in }) { $0.text(1) }) ?? []
        return names.contains(column)
    }
}
