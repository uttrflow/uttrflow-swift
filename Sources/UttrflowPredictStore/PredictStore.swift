package import Synchronization
import UttrflowCore
public import UttrflowPredict

public import struct Foundation.Date
public import class Foundation.FileManager
public import struct Foundation.URL

/// The evidence a candidate is built from, named once so the queries that read it cannot drift apart.
private let entryColumns = "text, count, accepted, rejected, self_sourced, last_used"

/// The corpus on disk: what the user has entered where, and what usually follows what.
public actor PredictStore: PredictionStore {
    /// How many entries one surface may hold before the weakest are evicted.
    public static let entriesPerSurface = 2_000

    /// How many candidates a query returns, which is more than any list shows.
    static let candidateLimit = 16

    /// The open file every read and write goes through.
    private var database: Database

    /// Opens the corpus, replacing a file that is not a database at all and refusing one from a newer build.
    public init(path: String) throws(PredictStoreError) {
        database = try Self.opened(at: path)
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

    /// What the user might be finishing, drawn from every folder of this field rather than only this one.
    public func candidates(
        for surface: Surface, matching typed: String
    ) throws(PredictStoreError) -> [Candidate] {
        guard !typed.isEmpty else { return [] }
        let typed = Spelling.canonical(typed)
        let ids = try surfaceIdentifiers(of: surface)
        guard !ids.isEmpty else { return [] }
        var exact: [Candidate] = []
        for id in ids { exact += try exactCandidates(surfaceIdentifier: id, typed: typed) }
        guard exact.isEmpty else { return merged(exact) }
        var fuzzy: [Candidate] = []
        for id in ids { fuzzy += try fuzzyCandidates(surfaceIdentifier: id, typed: typed) }
        return merged(fuzzy)
    }

    /// The lines this person recently entered in this field, each once, the ones from this document first.
    public func recent(in surface: Surface, limit: Int) throws(PredictStoreError) -> [String] {
        let ids = try surfaceIdentifiers(of: surface)
        guard !ids.isEmpty, limit > 0 else { return [] }
        let here = try identifier(of: surface, creating: false) ?? -1
        // One indexed read per scope, ordered and de-duplicated here, so SQLite groups nothing. See #880.
        var newest: [String: (used: Double, isHere: Bool)] = [:]
        var order: [String] = []
        for id in ids {
            for line in try recentLines(surfaceIdentifier: id, limit: limit) {
                let isHere = id == here
                guard let seen = newest[line.text] else {
                    newest[line.text] = (line.used, isHere)
                    order.append(line.text)
                    continue
                }
                newest[line.text] = (max(seen.used, line.used), seen.isHere || isHere)
            }
        }
        // The document in hand first, then the newest; arrival order breaks a tie, as the grouped read did.
        let ranked = order.enumerated().sorted { left, right in
            let one = newest[left.element] ?? (0, false)
            let other = newest[right.element] ?? (0, false)
            if one.isHere != other.isHere { return one.isHere }
            if one.used != other.used { return one.used > other.used }
            return left.offset < right.offset
        }
        return ranked.prefix(limit).map(\.element)
    }

    /// The per-scope recency read, exposed so a test can check its plan groups and sorts nothing.
    static let recentQuery = """
        SELECT text, last_used FROM entry
        WHERE surface_id = ? AND superseded_by IS NULL AND count > self_sourced
        ORDER BY last_used DESC LIMIT ?
        """

    /// One scope's most recent lines, read straight off `entry_recent` rather than grouped.
    private func recentLines(
        surfaceIdentifier id: Int64, limit: Int
    ) throws(PredictStoreError) -> [(text: String, used: Double)] {
        try database.rows(
            Self.recentQuery,
            {
                $0.bind(1, id)
                $0.bind(2, Int64(limit))
            }
        ) { ($0.text(0), $0.double(1)) }
    }

    /// How many compiled statements the open file keeps.
    var cachedStatements: Int { database.cachedStatements }

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

    /// Folds the same text learned in several places into one candidate, with its counts summed.
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
        return Self.strongest(order.compactMap { byText[$0] })
    }

    /// The candidates with the most evidence, compared across every folder before any is dropped.
    static func strongest(_ candidates: [Candidate]) -> [Candidate] {
        let ordered = candidates.sorted { first, second in
            let a = first.evidence
            let b = second.evidence
            return (second.editDistance, a?.count ?? 0, a?.lastUsed ?? .distantPast, second.text)
                > (first.editDistance, b?.count ?? 0, b?.lastUsed ?? .distantPast, first.text)
        }
        return Array(ordered.prefix(candidateLimit))
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
        let previous = Spelling.canonical(previous)
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

    /// The range scan the design rests on, over the lowercased text so case is ignored and the index kept.
    static let prefixQuery = """
        SELECT \(entryColumns) FROM entry
        WHERE surface_id = ? AND text_lower >= ? AND text_lower < ? AND superseded_by IS NULL
        ORDER BY count DESC LIMIT ?
        """

    /// Every candidate whose opening is what was typed, matched without regard to case.
    private func exactCandidates(
        surfaceIdentifier id: Int64, typed: String
    ) throws(PredictStoreError) -> [Candidate] {
        let lowered = typed.lowercased()
        guard let upper = Self.upperBound(of: lowered) else { return [] }
        return try readCandidates(
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
        let needle = FuzzyMatch.units(typed)
        let budget = FuzzyMatch.budget(forQueryOfLength: needle.count)
        guard budget > 0 else { return [] }
        let width = FuzzyMatch.maskWidth(forQueryOfLength: needle.count, within: budget)
        let queryMask = FuzzyMatch.mask(needle)

        // Filtered in SQL and then by mask, so only a line that matches is ever built into a `Candidate`.
        let shortest = max(0, needle.count - budget)
        let rows = try database.rows(
            """
            SELECT \(entryColumns) FROM entry
            WHERE surface_id = ? AND superseded_by IS NULL
                AND length(CAST(text AS BLOB)) >= ?
            """,
            {
                $0.bind(1, id)
                $0.bind(2, Int64(shortest))
            }
        ) { row -> Candidate? in
            Self.rowsScanned.withLock { $0 += 1 }
            let text = row.text(0)
            let units = FuzzyMatch.units(text)
            guard
                FuzzyMatch.couldMatch(
                    query: queryMask, candidate: FuzzyMatch.mask(units.prefix(width)), within: budget)
            else { return nil }
            let distance = FuzzyMatch.prefixDistance(needle, units, within: budget)
            guard distance <= budget else { return nil }
            return Candidate(
                text: text, source: .personal,
                evidence: Entry(
                    text: text, count: row.integer(1), accepted: row.integer(2),
                    rejected: row.integer(3), selfSourced: row.integer(4),
                    lastUsed: Date(timeIntervalSince1970: row.double(5))),
                editDistance: distance,
                isIrreversible: DestructiveCommand.matches(text))
        }
        return Self.strongest(rows.compactMap { $0 })
    }

    // MARK: - Writing

    /// Records a value the user finished entering, and what it followed, as one transaction.
    public func record(
        _ text: String, in surface: Surface, after previous: String? = nil,
        selfSourced: Bool = false, at moment: Date
    ) throws(PredictStoreError) {
        guard !text.isEmpty else { return }
        try database.transaction { () throws(PredictStoreError) in
            try write(
                Spelling.canonical(text), in: surface, after: previous.map(Spelling.canonical),
                selfSourced: selfSourced, at: moment)
        }
    }

    /// The steps of a record, which stand or fall together.
    private func write(
        _ text: String, in surface: Surface, after previous: String?, selfSourced: Bool, at moment: Date
    ) throws(PredictStoreError) {
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
              last_used = excluded.last_used,
              text_lower = excluded.text_lower
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
        try increment(.accepted, forText: text, in: surface)
    }

    /// Notes that a suggestion was shown and typed past, which is the user saying no.
    public func recordRejected(_ text: String, in surface: Surface) throws(PredictStoreError) {
        try increment(.rejected, forText: text, in: surface)
    }

    /// Marks an entry wrong and points at what replaces it, so it is never proposed again.
    public func supersede(
        _ text: String, with replacement: String, in surface: Surface
    ) throws(PredictStoreError) {
        guard let id = try identifier(of: surface, creating: false) else { return }
        try markSuperseded(
            Spelling.canonical(text), by: Spelling.canonical(replacement), surfaceIdentifier: id)
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
            $0.bind(2, Spelling.canonical(text))
        }
    }

    /// Forgets every surface, and with it every entry and succession they hold.
    public func forgetEverything() throws(PredictStoreError) {
        try database.execute("DELETE FROM surface")
    }

    /// How many entries each application has taught, keyed by bundle identifier.
    public func entryCountsByApplication() throws(PredictStoreError) -> [String: Int] {
        let counted = try database.rows(
            """
            SELECT bundle_id, COUNT(*) FROM entry
            JOIN surface ON surface.id = entry.surface_id
            GROUP BY bundle_id
            """, { _ in }
        ) { ($0.text(0), $0.integer(1)) }
        return Dictionary(counted, uniquingKeysWith: +)
    }

    /// How many entries the corpus holds across every surface.
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
            try markSuperseded(fragment, by: text, surfaceIdentifier: id)
        }
    }

    /// Points one entry at what replaces it, which is how a correction and a fragment are both retired.
    private func markSuperseded(
        _ text: String, by replacement: String, surfaceIdentifier id: Int64
    ) throws(PredictStoreError) {
        try database.run(
            "UPDATE entry SET superseded_by = ? WHERE surface_id = ? AND text = ?",
            {
                $0.bind(1, replacement)
                $0.bind(2, id)
                $0.bind(3, text)
            })
    }

    // MARK: - Plumbing

    /// A tally an offer moves, closed so nothing a caller supplied can reach the statement.
    private enum Tally: String {
        case accepted
        case rejected
    }

    /// Adds one to a tally against an entry, doing nothing where the field was never typed in.
    private func increment(
        _ tally: Tally, forText text: String, in surface: Surface
    ) throws(PredictStoreError) {
        guard let id = try identifier(of: surface, creating: false) else { return }
        let column = tally.rawValue
        try database.run("UPDATE entry SET \(column) = \(column) + 1 WHERE surface_id = ? AND text = ?") {
            $0.bind(1, id)
            $0.bind(2, Spelling.canonical(text))
        }
    }

    /// Keeps a surface within its cap, dropping superseded entries first and then the weakest.
    private func evictWeakest(surfaceIdentifier id: Int64) throws(PredictStoreError) {
        try evictWeakestSuccessions(surfaceIdentifier: id)
        let held = try database.rows(
            "SELECT COUNT(*) FROM entry WHERE surface_id = ?", { $0.bind(1, id) }
        ) { $0.integer(0) }
        guard let held = held.first, held > Self.entriesPerSurface else { return }
        try database.run(
            """
            DELETE FROM entry WHERE id IN (
              SELECT id FROM entry WHERE surface_id = ?
              ORDER BY (superseded_by IS NOT NULL) DESC, count ASC, last_used ASC LIMIT ?
            )
            """,
            {
                $0.bind(1, id)
                $0.bind(2, Int64(held - Self.entriesPerSurface))
            })
    }

    /// How many rows the fuzzy tier has looked at, which a test reads to bound the per-keystroke work.
    package static let rowsScanned = Mutex(0)
    /// Keeps a surface's successions within the same cap as its entries, dropping the least followed and then the oldest.
    private func evictWeakestSuccessions(surfaceIdentifier id: Int64) throws(PredictStoreError) {
        let held = try database.rows(
            "SELECT COUNT(*) FROM succession WHERE surface_id = ?", { $0.bind(1, id) }
        ) { $0.integer(0) }
        guard let held = held.first, held > Self.entriesPerSurface else { return }
        try database.run(
            """
            DELETE FROM succession WHERE rowid IN (
              SELECT rowid FROM succession WHERE surface_id = ? ORDER BY count ASC, rowid ASC LIMIT ?
            )
            """,
            {
                $0.bind(1, id)
                $0.bind(2, Int64(held - Self.entriesPerSurface))
            })
    }

    /// Reads a query returning the entry columns as candidates, each at the given edit distance.
    private func readCandidates(
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

    /// The evidence behind one entry, or nothing where it is unknown or has been retired.
    private func entry(surfaceIdentifier id: Int64, text: String) throws(PredictStoreError) -> Entry? {
        try readCandidates(
            """
            SELECT \(entryColumns) FROM entry
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
