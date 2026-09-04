import UttrflowCore
public import UttrflowPredict

public import struct Foundation.Date
public import class Foundation.FileManager
public import struct Foundation.URL

/// The corpus on disk: what the user has entered where, and what usually follows what.
public actor PredictStore: PredictionStore {
    /// How many entries one surface may hold before the weakest are evicted.
    public static let entriesPerSurface = 2_000

    /// How many candidates a query returns, which is more than any list shows.
    static let candidateLimit = 16

    private let path: String
    private var database: Database

    /// Opens the corpus, replacing a file that is not a database this app can read.
    public init(path: String) throws(PredictStoreError) {
        self.path = path
        self.database = try Self.opened(at: path)
    }

    /// Where the corpus lives, beside the clipboard and the history, versioned in its name.
    public static func defaultFile(in directory: URL) -> URL {
        LocalStore.file("predict.v1.sqlite", in: directory)
    }

    /// Opens and migrates, and on corruption starts again rather than leaving the app broken.
    private static func opened(at path: String) throws(PredictStoreError) -> Database {
        try? FileManager.default.createDirectory(
            at: URL(filePath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            let database = try Database(path: path)
            try Schema.migrate(database)
            return database
        } catch {
            guard error == .corrupt else { throw error }
            try? FileManager.default.removeItem(atPath: path)
            for suffix in ["-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
            let replacement = try Database(path: path)
            try Schema.migrate(replacement)
            return replacement
        }
    }

    // MARK: - Reading

    /// What the user might be finishing, drawn from every folder in this app they have typed it, not walled off by one.
    public func candidates(
        for surface: Surface, matching typed: String
    ) throws(PredictStoreError) -> [Candidate] {
        guard !typed.isEmpty else { return [] }
        let ids = try surfaceIdentifiers(of: surface)
        guard !ids.isEmpty else { return [] }
        var exact: [Candidate] = []
        for id in ids { exact += try exactCandidates(surfaceIdentifier: id, typed: typed) }
        guard exact.isEmpty else { return merged(exact) }
        var fuzzy: [Candidate] = []
        for id in ids { fuzzy += try fuzzyCandidates(surfaceIdentifier: id, typed: typed) }
        return merged(fuzzy)
    }

    /// The lines this person most recently entered in this field, newest first and each once, which is how they write here.
    public func recent(in surface: Surface, limit: Int) throws(PredictStoreError) -> [String] {
        let ids = try surfaceIdentifiers(of: surface)
        guard !ids.isEmpty, limit > 0 else { return [] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        return try database.rows(
            """
            SELECT text, MAX(last_used) AS used FROM entry
            WHERE surface_id IN (\(placeholders)) AND superseded_by IS NULL
            GROUP BY text ORDER BY used DESC LIMIT ?
            """,
            { statement in
                for (offset, id) in ids.enumerated() { statement.bind(Int32(offset + 1), id) }
                statement.bind(Int32(ids.count + 1), Int64(limit))
            }
        ) { $0.text(0) }
    }

    /// Every surface that is the same field in the same application, whatever document it was in.
    private func surfaceIdentifiers(of surface: Surface) throws(PredictStoreError) -> [Int64] {
        try database.rows(
            "SELECT id FROM surface WHERE bundle_id = ? AND role = ? AND locator = ?",
            {
                $0.bind(1, surface.bundleIdentifier)
                $0.bind(2, surface.role)
                $0.bind(3, surface.locator ?? "")
            }
        ) { Int64($0.integer(0)) }
    }

    /// Folds the same text learned in several places into one candidate, its counts summed so it ranks by real use.
    private func merged(_ candidates: [Candidate]) -> [Candidate] {
        var byText: [String: Candidate] = [:]
        var order: [String] = []
        for candidate in candidates {
            guard let existing = byText[candidate.text] else {
                byText[candidate.text] = candidate
                order.append(candidate.text)
                continue
            }
            byText[candidate.text] = Self.combine(existing, candidate)
        }
        return Array(order.compactMap { byText[$0] }.prefix(Self.candidateLimit))
    }

    /// One text known in two surfaces becomes one candidate: evidence summed, the nearer edit kept.
    private static func combine(_ first: Candidate, _ second: Candidate) -> Candidate {
        let evidence: Entry?
        if let a = first.evidence, let b = second.evidence {
            evidence = Entry(
                text: a.text, count: a.count + b.count, accepted: a.accepted + b.accepted,
                rejected: a.rejected + b.rejected, selfSourced: a.selfSourced + b.selfSourced,
                lastUsed: max(a.lastUsed, b.lastUsed))
        } else {
            evidence = first.evidence ?? second.evidence
        }
        return Candidate(
            text: first.text, source: first.source, evidence: evidence,
            editDistance: min(first.editDistance, second.editDistance),
            isIrreversible: first.isIrreversible)
    }

    /// What usually follows what was last entered here, for a field nothing has been typed into.
    public func successors(
        for surface: Surface, after previous: String
    ) throws(PredictStoreError) -> [Candidate] {
        guard let id = try identifier(of: surface, creating: false) else { return [] }
        let texts = try database.rows(
            """
            SELECT next FROM succession WHERE surface_id = ? AND previous = ?
            ORDER BY count DESC LIMIT ?
            """,
            {
                $0.bind(1, id)
                $0.bind(2, previous)
                $0.bind(3, Int64(Self.candidateLimit))
            }, { $0.text(0) })
        var candidates: [Candidate] = []
        for text in texts {
            guard let evidence = try entry(surfaceIdentifier: id, text: text) else { continue }
            candidates.append(
                Candidate(
                    text: text, source: .succession, evidence: evidence,
                    isIrreversible: DestructiveCommand.matches(text)))
        }
        return candidates
    }

    /// The range scan the whole design rests on, over the lowercased text so it ignores case yet keeps the index.
    static let prefixQuery = """
        SELECT text, count, accepted, rejected, self_sourced, last_used FROM entry
        WHERE surface_id = ? AND text_lower >= ? AND text_lower < ? AND superseded_by IS NULL
        ORDER BY count DESC LIMIT ?
        """

    /// Every candidate whose opening is what was typed, matched without regard to case.
    private func exactCandidates(
        surfaceIdentifier id: Int64, typed: String
    ) throws(PredictStoreError) -> [Candidate] {
        let lowered = typed.lowercased()
        guard let upper = Self.upperBound(of: lowered) else { return [] }
        return try rows(
            Self.prefixQuery,
            {
                $0.bind(1, id)
                $0.bind(2, lowered)
                $0.bind(3, upper)
                $0.bind(4, Int64(Self.candidateLimit))
            }, distance: 0)
    }

    /// The fallback, run only when nothing matched exactly, behind the character-mask filter.
    private func fuzzyCandidates(
        surfaceIdentifier id: Int64, typed: String
    ) throws(PredictStoreError) -> [Candidate] {
        let needle = Array(typed.utf8)
        let budget = FuzzyMatch.budget(forQueryOfLength: needle.count)
        guard budget > 0 else { return [] }
        let width = FuzzyMatch.maskWidth(forQueryOfLength: needle.count, within: budget)
        let queryMask = FuzzyMatch.mask(needle)

        let all = try rows(
            """
            SELECT text, count, accepted, rejected, self_sourced, last_used FROM entry
            WHERE surface_id = ? AND superseded_by IS NULL
            """, { $0.bind(1, id) }, distance: 0)

        var matched: [Candidate] = []
        for candidate in all {
            let bytes = Array(candidate.text.utf8)
            guard
                FuzzyMatch.couldMatch(
                    query: queryMask, candidate: FuzzyMatch.mask(bytes.prefix(width)), within: budget)
            else { continue }
            let distance = FuzzyMatch.prefixDistance(needle, bytes, within: budget)
            guard distance <= budget else { continue }
            matched.append(
                Candidate(
                    text: candidate.text, source: candidate.source, evidence: candidate.evidence,
                    editDistance: distance, isIrreversible: candidate.isIrreversible))
        }
        return Array(matched.prefix(Self.candidateLimit))
    }

    // MARK: - Writing

    /// Records a value the user finished entering, and what it followed.
    public func record(
        _ text: String, in surface: Surface, after previous: String? = nil,
        selfSourced: Bool = false, at moment: Date
    ) throws(PredictStoreError) {
        guard !text.isEmpty else { return }
        guard let id = try identifier(of: surface, creating: true) else { return }
        // A half-typed fragment is not stored when a longer line the user already entered begins with it.
        if try isFragmentOfLongerEntry(surfaceIdentifier: id, text: text) { return }
        try database.run(
            """
            INSERT INTO entry (surface_id, text, text_lower, count, self_sourced, last_used)
            VALUES (?, ?, ?, 1, ?, ?)
            ON CONFLICT (surface_id, text) DO UPDATE SET
              count = count + 1,
              self_sourced = self_sourced + excluded.self_sourced,
              last_used = excluded.last_used
            """,
            {
                $0.bind(1, id)
                $0.bind(2, text)
                $0.bind(3, text.lowercased())
                $0.bind(4, Int64(selfSourced ? 1 : 0))
                $0.bind(5, moment.timeIntervalSince1970)
            })
        // This whole value retires the shorter fragments it grew out of, so only it is ever proposed.
        try supersedeFragments(surfaceIdentifier: id, of: text)
        if let previous, !previous.isEmpty {
            try database.run(
                """
                INSERT INTO succession (surface_id, previous, next, count) VALUES (?, ?, ?, 1)
                ON CONFLICT (surface_id, previous, next) DO UPDATE SET count = count + 1
                """,
                {
                    $0.bind(1, id)
                    $0.bind(2, previous)
                    $0.bind(3, text)
                })
        }
        try evictWeakest(surfaceIdentifier: id)
    }

    /// Notes that a suggestion was taken, which is evidence and also a discount.
    public func recordAccepted(_ text: String, in surface: Surface) throws(PredictStoreError) {
        try count("accepted", text, surface)
    }

    /// Notes that a suggestion was shown and typed past, which is the user saying no.
    public func recordRejected(_ text: String, in surface: Surface) throws(PredictStoreError) {
        try count("rejected", text, surface)
    }

    /// Marks an entry wrong and points at what replaces it, so it is never proposed again.
    public func supersede(
        _ text: String, with replacement: String, in surface: Surface
    ) throws(PredictStoreError) {
        guard let id = try identifier(of: surface, creating: false) else { return }
        try database.run(
            "UPDATE entry SET superseded_by = ? WHERE surface_id = ? AND text = ?",
            {
                $0.bind(1, replacement)
                $0.bind(2, id)
                $0.bind(3, text)
            })
    }

    // MARK: - Forgetting

    /// Forgets everything learned in one application.
    public func forget(bundleIdentifier: String) throws(PredictStoreError) {
        try database.run("DELETE FROM surface WHERE bundle_id = ?") { $0.bind(1, bundleIdentifier) }
    }

    /// Forgets one entry, wherever the user noticed it.
    public func forget(_ text: String, in surface: Surface) throws(PredictStoreError) {
        guard let id = try identifier(of: surface, creating: false) else { return }
        try database.run("DELETE FROM entry WHERE surface_id = ? AND text = ?") {
            $0.bind(1, id)
            $0.bind(2, text)
        }
    }

    /// Forgets everything, which is the reset in Settings.
    public func forgetEverything() throws(PredictStoreError) {
        try database.execute("DELETE FROM surface")
    }

    /// How many entries are held, for the tests and the diagnostics page.
    public func entryCount() throws(PredictStoreError) -> Int {
        try database.rows("SELECT COUNT(*) FROM entry", { _ in }) { $0.integer(0) }.first ?? 0
    }

    // MARK: - Prefix hygiene

    /// Whether a longer non-superseded line the user entered begins with this one, making it a fragment.
    private func isFragmentOfLongerEntry(
        surfaceIdentifier id: Int64, text: String
    ) throws(PredictStoreError) -> Bool {
        let lowered = text.lowercased()
        let length = Int64(lowered.count)
        let found = try database.rows(
            """
            SELECT 1 FROM entry
            WHERE surface_id = ? AND superseded_by IS NULL
              AND length(text_lower) > ? AND substr(text_lower, 1, ?) = ?
            LIMIT 1
            """,
            {
                $0.bind(1, id)
                $0.bind(2, length)
                $0.bind(3, length)
                $0.bind(4, lowered)
            }
        ) { $0.integer(0) }
        return !found.isEmpty
    }

    /// Retires every shorter non-superseded entry that this value begins with, pointing each at this value.
    private func supersedeFragments(
        surfaceIdentifier id: Int64, of text: String
    ) throws(PredictStoreError) {
        let lowered = text.lowercased()
        let fragments = try database.rows(
            """
            SELECT text FROM entry
            WHERE surface_id = ? AND superseded_by IS NULL AND text <> ?
              AND length(text_lower) < ? AND text_lower = substr(?, 1, length(text_lower))
            """,
            {
                $0.bind(1, id)
                $0.bind(2, text)
                $0.bind(3, Int64(lowered.count))
                $0.bind(4, lowered)
            }
        ) { $0.text(0) }
        for fragment in fragments {
            try database.run(
                "UPDATE entry SET superseded_by = ? WHERE surface_id = ? AND text = ?",
                {
                    $0.bind(1, text)
                    $0.bind(2, id)
                    $0.bind(3, fragment)
                })
        }
    }

    // MARK: - Plumbing

    private func count(_ column: String, _ text: String, _ surface: Surface) throws(PredictStoreError) {
        guard let id = try identifier(of: surface, creating: false) else { return }
        // The column is one of two literals chosen here, never anything a caller supplied.
        let sql = "UPDATE entry SET \(column) = \(column) + 1 WHERE surface_id = ? AND text = ?"
        try database.run(sql) {
            $0.bind(1, id)
            $0.bind(2, text)
        }
    }

    /// Keeps a surface within its cap, dropping the entries with the least behind them.
    private func evictWeakest(surfaceIdentifier id: Int64) throws(PredictStoreError) {
        let held = try database.rows(
            "SELECT COUNT(*) FROM entry WHERE surface_id = ?", { $0.bind(1, id) }
        ) { $0.integer(0) }
        guard let held = held.first, held > Self.entriesPerSurface else { return }
        try database.run(
            """
            DELETE FROM entry WHERE id IN (
              SELECT id FROM entry WHERE surface_id = ?
              ORDER BY count ASC, last_used ASC LIMIT ?
            )
            """,
            {
                $0.bind(1, id)
                $0.bind(2, Int64(held - Self.entriesPerSurface))
            })
    }

    private func rows(
        _ sql: String, _ bind: (OpaquePointer) -> Void, distance: Int
    ) throws(PredictStoreError) -> [Candidate] {
        try database.rows(sql, bind) { row in
            Candidate(
                text: row.text(0),
                source: .personal,
                evidence: Entry(
                    text: row.text(0), count: row.integer(1), accepted: row.integer(2),
                    rejected: row.integer(3), selfSourced: row.integer(4),
                    lastUsed: Date(timeIntervalSince1970: row.double(5))),
                editDistance: distance,
                isIrreversible: DestructiveCommand.matches(row.text(0)))
        }
    }

    private func entry(surfaceIdentifier id: Int64, text: String) throws(PredictStoreError) -> Entry? {
        try rows(
            """
            SELECT text, count, accepted, rejected, self_sourced, last_used FROM entry
            WHERE surface_id = ? AND text = ? AND superseded_by IS NULL
            """,
            {
                $0.bind(1, id)
                $0.bind(2, text)
            }, distance: 0
        ).first?.evidence
    }

    /// Finds the surface's row, creating it only when something is about to be written.
    private func identifier(of surface: Surface, creating: Bool) throws(PredictStoreError) -> Int64? {
        let bind: (OpaquePointer) -> Void = {
            $0.bind(1, surface.bundleIdentifier)
            $0.bind(2, surface.role)
            $0.bind(3, surface.locator ?? "")
            $0.bind(4, surface.scope ?? "")
        }
        let found = try database.rows(
            "SELECT id FROM surface WHERE bundle_id = ? AND role = ? AND locator = ? AND scope = ?",
            bind
        ) { Int64($0.integer(0)) }
        if let existing = found.first { return existing }
        guard creating else { return nil }
        try database.run(
            "INSERT INTO surface (bundle_id, role, locator, scope) VALUES (?, ?, ?, ?)", bind)
        return database.lastInsertedIdentifier
    }

    /// The end of a prefix range, so `git c` scans up to but not including `git d`.
    static func upperBound(of prefix: String) -> String? {
        guard let last = prefix.unicodeScalars.last,
            let next = Unicode.Scalar(last.value + 1)
        else { return nil }
        return String(prefix.unicodeScalars.dropLast()) + String(next)
    }
}
