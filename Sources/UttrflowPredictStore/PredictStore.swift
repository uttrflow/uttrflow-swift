package import Synchronization
public import UttrflowCore
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

    /// How many documents one field may retain before its least recently used scope is removed.
    public static let surfacesPerField = 64

    /// Free pages accumulated before the store reclaims disk space.
    static let compactionThresholdPages = 64

    /// How many candidates a query returns, which is more than any list shows.
    static let candidateLimit = 16

    /// The open file every read and write goes through.
    private(set) var database: Database

    /// Opens the corpus, replacing a file that is not a database at all and refusing one from a newer build.
    public init(path: String, encryptedStore: EncryptedStore? = nil) throws(PredictStoreError) {
        database = try Self.opened(at: path, encryptedStore: encryptedStore)
    }

    /// Where the corpus lives, beside the clipboard and the history, versioned in its name.
    public static func defaultFile(in directory: URL) -> URL {
        LocalStoreEntry.predict.location(in: directory)
    }

    /// Opens and migrates, and on corruption starts again rather than leaving the app broken.
    private static func opened(
        at path: String, encryptedStore: EncryptedStore?
    ) throws(PredictStoreError) -> Database {
        try? PrivateFile.makeDirectory(at: URL(filePath: path).deletingLastPathComponent())
        do {
            let database = try Database(path: path, encryptedStore: encryptedStore)
            try Schema.migrate(database)
            try database.finishOpening()
            if encryptedStore == nil {
                // A migration may have deleted forgotten lines; their old pages must not stay in the log.
                _ = try? database.rows("PRAGMA wal_checkpoint(TRUNCATE)", { _ in }) { $0.integer(0) }
                secureFiles(at: path)
            }
            return database
        } catch {
            guard error == .corrupt else { throw error }
            setAsideCorrupt(at: path)
            let replacement = try Database(path: path, encryptedStore: encryptedStore)
            try Schema.migrate(replacement)
            try replacement.finishOpening()
            if encryptedStore == nil { secureFiles(at: path) }
            return replacement
        }
    }

    /// Moves a corrupt database and its sidecars aside under the JSON stores' convention, deleting only what cannot move.
    private static func setAsideCorrupt(at path: String) {
        let now = Date()
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(filePath: path + suffix)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                continue
            }
            if LocalStore.setAside(url, now: now) == nil {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Deletes every copy of the corpus and its sidecars that an earlier open set aside.
    public static func removeSetAsideCopies(at path: String) throws {
        var refusal: (any Error)?
        for suffix in ["", "-wal", "-shm"] {
            do { try LocalStore.removeSetAside(URL(filePath: path + suffix)) } catch {
                refusal = refusal ?? error
            }
        }
        if let refusal { throw refusal }
    }

    /// Deletes the corpus and its sidecars without opening them, for a corpus this build cannot open.
    public static func removeFiles(at path: String) throws {
        let files = ["", "-wal", "-shm"].map { URL(filePath: path + $0) }.filter {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        }
        try LocalStore.removeEach(files)
    }

    /// SQLite owns these files in the legacy mode, so each remains private and backup-excluded.
    private static func secureFiles(at path: String) {
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(filePath: path + suffix)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
            try? PrivateFile.tighten(at: url)
            try? PrivateFile.excludeFromBackup(at: url)
        }
    }

    // MARK: - Reading

    /// What the user might be finishing, drawn from this folder and the field's most recently used others.
    public func candidates(
        for surface: Surface, matching typed: String
    ) throws(PredictStoreError) -> [Candidate] {
        guard !typed.isEmpty else { return [] }
        let typed = Spelling.canonical(typed)
        let ids = try surfaceIdentifiers(of: surface)
        guard !ids.isEmpty else { return [] }
        let here = try identifier(of: surface, creating: false)
        var exact: [Candidate] = []
        for id in ids { exact += try exactCandidates(surfaceIdentifier: id, typed: typed) }
        exact = try withoutRetired(exact, here: here)
        guard exact.isEmpty else { return merged(exact) }
        var fuzzy: [Candidate] = []
        for id in ids { fuzzy += try fuzzyCandidates(surfaceIdentifier: id, typed: typed) }
        return merged(try withoutRetired(fuzzy, here: here))
    }

    /// Drops what was retired in this folder, even where another folder still offers it.
    private func withoutRetired(
        _ candidates: [Candidate], here: Int64?
    ) throws(PredictStoreError) -> [Candidate] {
        guard let here, !candidates.isEmpty else { return candidates }
        let withheld = try withheldTexts(among: candidates.map(\.text), surfaceIdentifier: here)
        return withheld.isEmpty ? candidates : candidates.filter { !withheld.contains($0.text) }
    }

    /// The lines this person recently entered in this field, each once, the ones from this document first.
    public func recent(in surface: Surface, limit: Int) throws(PredictStoreError) -> [String] {
        let ids = try surfaceIdentifiers(of: surface)
        guard !ids.isEmpty, limit > 0 else { return [] }
        let here = try identifier(of: surface, creating: false) ?? -1
        // One indexed read per scope, ordered and de-duplicated here, so SQLite groups nothing. See #880.
        var scopes: [(id: Int64, lines: [(text: String, used: Double)])] = []
        for id in ids { scopes.append((id, try recentLines(surfaceIdentifier: id, limit: limit))) }
        let withheld = try withheldTexts(
            among: scopes.flatMap { $0.lines.map(\.text) }, surfaceIdentifier: here)
        var newest: [String: (used: Double, isHere: Bool)] = [:]
        var order: [String] = []
        for (id, lines) in scopes {
            for line in lines where !withheld.contains(line.text) {
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

    /// Which of these lines this folder retired or forgot, so one borrowed from another folder does not come back.
    private func withheldTexts(
        among texts: [String], surfaceIdentifier id: Int64
    ) throws(PredictStoreError) -> Set<String> {
        var withheld = Set(
            try database.rows(
                "SELECT text FROM entry WHERE surface_id = ? AND superseded_by IS NOT NULL",
                { $0.bind(1, id) }
            ) { $0.text(0) })
        let markers = Set(try forgottenMarkers(surfaceIdentifier: id))
        guard !markers.isEmpty else { return withheld }
        let marker = try ForgottenMarker(database)
        for text in Set(texts) where !withheld.contains(text) {
            if markers.contains(try marker(text)) { withheld.insert(text) }
        }
        return withheld
    }

    /// The digests of every line forgotten in this folder.
    private func forgottenMarkers(surfaceIdentifier id: Int64) throws(PredictStoreError) -> [String] {
        try database.rows("SELECT marker FROM forgotten WHERE surface_id = ?", { $0.bind(1, id) }) {
            $0.text(0)
        }
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

    /// How many documents of one field a lookup reads, so its cost does not grow with every folder ever used.
    static let scopeLimit = 8

    /// The same field in the same application: this document first, then the most recently used others.
    static let scopeQuery = """
        SELECT id FROM surface
        WHERE bundle_id = ? AND role = ? AND locator = ?
        ORDER BY scope = ? DESC, last_used DESC, id DESC
        LIMIT ?
        """

    /// The documents of this field a lookup reads, bounded by `scopeLimit`.
    private func surfaceIdentifiers(of surface: Surface) throws(PredictStoreError) -> [Int64] {
        try database.rows(
            Self.scopeQuery,
            {
                $0.bind(1, surface.bundleIdentifier)
                $0.bind(2, surface.role)
                $0.bind(3, surface.locator ?? "")
                $0.bind(4, surface.scope ?? "")
                $0.bind(5, Int64(Self.scopeLimit))
            }
        ) { Int64($0.integer(0)) }
    }

    /// Folds the same text learned in several places into one candidate, with its counts summed.
    private func merged(_ candidates: [Candidate]) -> [Candidate] {
        var byText: [String: Candidate] = [:]
        var order: [String] = []
        for candidate in candidates {
            let key = candidate.text.lowercased()
            guard let existing = byText[key] else {
                byText[key] = candidate
                order.append(key)
                continue
            }
            byText[key] = Self.combine(existing, candidate)
        }
        return Self.strongest(order.compactMap { byText[$0] })
    }

    /// The candidates ranking would score highest, compared across every folder before any is dropped.
    static func strongest(_ candidates: [Candidate]) -> [Candidate] {
        // Decay scales every score alike from any later moment, so the newest use orders them as ranking would.
        let latest = candidates.compactMap(\.evidence?.lastUsed).max() ?? .distantPast
        let scored = candidates.map { (candidate: $0, score: Frecency.score($0, now: latest)) }
        let ordered = scored.sorted { first, second in
            (second.candidate.editDistance, first.score, second.candidate.text)
                > (first.candidate.editDistance, second.score, first.candidate.text)
        }
        return ordered.prefix(candidateLimit).map(\.candidate)
    }

    /// One text known in two surfaces becomes one candidate: evidence summed, the nearer edit kept.
    private static func combine(_ first: Candidate, _ second: Candidate) -> Candidate {
        let evidence: Entry?
        if let a = first.evidence, let b = second.evidence {
            evidence = Entry(
                text: b.lastUsed > a.lastUsed ? b.text : a.text, count: a.count + b.count,
                accepted: a.accepted + b.accepted,
                rejected: a.rejected + b.rejected, selfSourced: a.selfSourced + b.selfSourced,
                lastUsed: max(a.lastUsed, b.lastUsed))
        } else {
            evidence = first.evidence ?? second.evidence
        }
        // The spelling used most recently is the one offered.
        let firstUsed = first.evidence?.lastUsed ?? .distantPast
        let newer = (second.evidence?.lastUsed ?? .distantPast) > firstUsed
        return Candidate(
            text: newer ? second.text : first.text, source: first.source, evidence: evidence,
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
                    isIrreversible: DestructiveCommand.matches(text, failClosedOnUnresolved: true)))
        }
        return candidates
    }

    /// The range scan the design rests on, over the lowercased text so case is ignored and the index kept.
    static let prefixQuery = """
        SELECT \(entryColumns) FROM entry
        WHERE surface_id = ? AND text_lower >= ? AND text_lower < ? AND superseded_by IS NULL
        ORDER BY count DESC LIMIT ?
        """

    /// The same range scan newest first, so a line used lately is read however many older lines outnumber it.
    static let recentPrefixQuery = """
        SELECT \(entryColumns) FROM entry
        WHERE surface_id = ? AND text_lower >= ? AND text_lower < ? AND superseded_by IS NULL
        ORDER BY last_used DESC LIMIT ?
        """

    /// The most used and the most recent candidates whose opening is what was typed, each once, matched without regard to case.
    private func exactCandidates(
        surfaceIdentifier id: Int64, typed: String
    ) throws(PredictStoreError) -> [Candidate] {
        let lowered = typed.lowercased()
        guard let upper = Self.upperBound(of: lowered) else { return [] }
        var seen: Set<String> = []
        var found: [Candidate] = []
        for query in [Self.prefixQuery, Self.recentPrefixQuery] {
            let read = try readCandidates(
                query,
                {
                    $0.bind(1, id)
                    $0.bind(2, lowered)
                    $0.bind(3, upper)
                    $0.bind(4, Int64(Self.candidateLimit))
                }, distance: 0)
            // Only a row both queries returned is dropped; case variants are summed later by `merged`.
            found += read.filter { seen.insert($0.text).inserted }
        }
        return found
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
            // A near miss that would add, drop or change a typed digit writes a different number, never a fixed typo.
            guard distance <= budget, FuzzyMatch.keepsDigits(of: needle, in: units, atDistance: distance)
            else {
                return nil
            }
            return Candidate(
                text: text, source: .personal,
                evidence: Entry(
                    text: text, count: row.integer(1), accepted: row.integer(2),
                    rejected: row.integer(3), selfSourced: row.integer(4),
                    lastUsed: Self.clampedLastUsed(row.double(5))),
                editDistance: distance,
                isIrreversible: DestructiveCommand.matches(text, failClosedOnUnresolved: true))
        }
        return Self.strongest(rows.compactMap { $0 })
    }

    // MARK: - Writing

    /// Records a value the user finished entering, and what it followed, as one transaction.
    public func record(
        _ text: String, in surface: Surface, after previous: String? = nil,
        as origin: LineOrigin = .typed, at moment: Date
    ) throws(PredictStoreError) {
        guard !text.isEmpty else { return }
        let moment = min(moment, Date())
        try database.transaction { () throws(PredictStoreError) in
            try write(
                Spelling.canonical(text), in: surface, after: previous.map(Spelling.canonical),
                as: origin, at: moment)
        }
        try? compactIfNeeded()
    }

    /// Keeps a stored clock jump from outranking entries used at the actual current time.
    private static func clampedLastUsed(_ timestamp: Double) -> Date {
        min(Date(timeIntervalSince1970: timestamp), Date())
    }

    /// The steps of a record, which stand or fall together.
    private func write(
        _ text: String, in surface: Surface, after previous: String?, as origin: LineOrigin, at moment: Date
    ) throws(PredictStoreError) {
        guard let id = try identifier(of: surface, creating: true) else { return }
        try database.run("UPDATE surface SET last_used = MAX(last_used, ?) WHERE id = ?") {
            $0.bind(1, moment.timeIntervalSince1970)
            $0.bind(2, id)
        }
        // A forgotten line comes back only when typed by hand; an accepted suggestion of it stays unstored.
        if try !forgottenMarkers(surfaceIdentifier: id).isEmpty {
            let digest = try ForgottenMarker(database)(text)
            let cleared = try database.run("DELETE FROM forgotten WHERE surface_id = ? AND marker = ?") {
                $0.bind(1, id)
                $0.bind(2, digest)
            }
            if cleared > 0, origin.isSelfSourced { return }
        }
        // An unfinished fragment is not stored when a longer line the user already entered begins with it.
        if origin != .finished, try isFragmentOfLongerEntry(surfaceIdentifier: id, text: text),
            try !holdsFinishedLine(text, surfaceIdentifier: id)
        {
            return
        }
        try database.run(
            """
            INSERT INTO entry (surface_id, text, text_lower, count, self_sourced, finished, last_used)
            VALUES (?, ?, ?, 1, ?, ?, ?)
            ON CONFLICT (surface_id, text) DO UPDATE SET
              count = count + 1,
              self_sourced = self_sourced + excluded.self_sourced,
              finished = MAX(finished, excluded.finished),
              last_used = excluded.last_used,
              text_lower = excluded.text_lower,
              superseded_by = CASE
                WHEN excluded.self_sourced = 0 THEN NULL
                ELSE entry.superseded_by
              END
            """,
            {
                $0.bind(1, id)
                $0.bind(2, text)
                $0.bind(3, text.lowercased())
                $0.bind(4, Int64(origin.isSelfSourced ? 1 : 0))
                $0.bind(5, Int64(origin == .finished ? 1 : 0))
                $0.bind(6, moment.timeIntervalSince1970)
            })
        // Typing the line by hand takes back every refusal of it in this field, which is what brings a retired line back.
        if !origin.isSelfSourced { try forgiveRefusals(of: text, in: surface) }
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
        try evictWeakest(
            surfaceIdentifier: id, protecting: text,
            succession: previous.map { (previous: $0, next: text) })
        try evictOldestSurfaces(
            bundleIdentifier: surface.bundleIdentifier, role: surface.role, locator: surface.locator ?? "",
            keepingSurface: id)
    }

    /// Notes that a suggestion was taken, which is evidence and also a discount.
    public func recordAccepted(_ text: String, in surface: Surface) throws(PredictStoreError) {
        try increment(.accepted, forText: text, in: surface)
    }

    /// Notes that a suggestion was shown and typed past, which is the user saying no.
    public func recordRejected(_ text: String, in surface: Surface) throws(PredictStoreError) {
        try increment(.rejected, forText: text, in: surface)
    }

    /// Takes back one acceptance the person undid: the use and the acceptance it added, and the line when that was all it held.
    public func retractAcceptance(_ text: String, in surface: Surface) throws(PredictStoreError) {
        let text = Spelling.canonical(text)
        try database.transaction { () throws(PredictStoreError) in
            guard let entry = try supplier(of: text, in: surface) else { return }
            try database.run(
                """
                UPDATE entry SET count = count - 1, accepted = accepted - 1, self_sourced = self_sourced - 1
                WHERE id = ? AND count > 0 AND accepted > 0 AND self_sourced > 0
                """
            ) { $0.bind(1, entry) }
            try database.run("DELETE FROM entry WHERE id = ? AND count = 0 AND superseded_by IS NULL") {
                $0.bind(1, entry)
            }
        }
    }

    /// Marks an entry wrong in this folder and points at what replaces it, unless the person finished that line.
    public func supersede(
        _ text: String, with replacement: String, in surface: Surface
    ) throws(PredictStoreError) {
        let text = Spelling.canonical(text)
        let replacement = Spelling.canonical(replacement)
        try database.transaction { () throws(PredictStoreError) in
            guard let supplier = try supplier(of: text, in: surface), try !isFinished(entry: supplier),
                let id = try identifier(of: surface, creating: true)
            else { return }
            try database.run("UPDATE surface SET last_used = MAX(last_used, ?) WHERE id = ?") {
                $0.bind(1, Date().timeIntervalSince1970)
                $0.bind(2, id)
            }
            // A line borrowed from another folder is retired here by a row that holds no uses of its own.
            try database.run(
                """
                INSERT INTO entry (surface_id, text, text_lower, count, last_used, superseded_by)
                VALUES (?, ?, ?, 0, 0, ?)
                ON CONFLICT (surface_id, text) DO UPDATE SET superseded_by = excluded.superseded_by
                """,
                {
                    $0.bind(1, id)
                    $0.bind(2, text)
                    $0.bind(3, text.lowercased())
                    $0.bind(4, replacement)
                })
            try evictWeakest(surfaceIdentifier: id)
        }
        try? compactIfNeeded()
    }

    // MARK: - Forgetting

    /// Forgets everything learned in one application.
    public func forget(bundleIdentifier: String) throws(PredictStoreError) {
        try database.run("DELETE FROM surface WHERE bundle_id = ?") {
            $0.bind(1, ApplicationKey.of(bundleIdentifier))
        }
        leaveNothingBehind()
    }

    /// Retires one entry in this scope, and every succession naming it, so other scopes cannot offer it here.
    public func forget(_ text: String, in surface: Surface) throws(PredictStoreError) {
        guard let id = try identifier(of: surface, creating: false) else { return }
        let text = Spelling.canonical(text)
        try database.transaction { () throws(PredictStoreError) in
            try database.run("UPDATE surface SET last_used = MAX(last_used, ?) WHERE id = ?") {
                $0.bind(1, Date().timeIntervalSince1970)
                $0.bind(2, id)
            }
            try database.run("DELETE FROM entry WHERE surface_id = ? AND text = ?") {
                $0.bind(1, id)
                $0.bind(2, text)
            }
            // Keep only a keyed digest, so copies read from other scopes stay forgotten here without the line on disk.
            let digest = try ForgottenMarker(database)(text)
            try database.run("INSERT OR IGNORE INTO forgotten (surface_id, marker) VALUES (?, ?)") {
                $0.bind(1, id)
                $0.bind(2, digest)
            }
            try database.run("DELETE FROM succession WHERE surface_id = ? AND (previous = ? OR next = ?)") {
                $0.bind(1, id)
                $0.bind(2, text)
                $0.bind(3, text)
            }
        }
        leaveNothingBehind()
    }

    /// Forgets every surface, and with it every entry and succession they hold.
    public func forgetEverything() throws(PredictStoreError) {
        try database.execute("DELETE FROM surface")
        leaveNothingBehind()
    }

    /// Removes every stored line `refuses` matches, once for each new `version` of the rule called `name`, and counts the lines removed.
    @discardableResult
    public func sweep(
        _ name: String, version: Int, removing refuses: @Sendable (String) -> Bool
    ) throws(PredictStoreError) -> Int {
        try sweep(name, version: version) { text, _ in refuses(text) }
    }

    /// Removes every stored line `refuses` matches on its surface, once per `version`, and counts the lines removed.
    @discardableResult
    public func sweep(
        _ name: String, version: Int, removing refuses: @Sendable (String, Surface) -> Bool
    ) throws(PredictStoreError) -> Int {
        let swept = try database.rows("SELECT version FROM sweep WHERE name = ?", { $0.bind(1, name) }) {
            $0.integer(0)
        }
        if let swept = swept.first, swept >= version { return 0 }
        var removed = 0
        try database.transaction { () throws(PredictStoreError) in
            let entries = try database.rows(
                """
                SELECT entry.id, entry.text, entry.superseded_by,
                       surface.bundle_id, surface.role, surface.locator, surface.scope
                FROM entry JOIN surface ON surface.id = entry.surface_id
                """, { _ in }
            ) {
                (
                    Int64($0.integer(0)), $0.text(1), $0.optionalText(2),
                    Surface(
                        bundleIdentifier: $0.text(3), role: $0.text(4), locator: $0.text(5),
                        scope: $0.text(6))
                )
            }
            for (id, text, replacement, surface) in entries
            where refuses(text, surface) || replacement.map({ refuses($0, surface) }) == true {
                try database.run("DELETE FROM entry WHERE id = ?") { $0.bind(1, id) }
                removed += 1
            }
            let successions = try database.rows(
                """
                SELECT succession.rowid, succession.previous, succession.next,
                       surface.bundle_id, surface.role, surface.locator, surface.scope
                FROM succession JOIN surface ON surface.id = succession.surface_id
                """, { _ in }
            ) {
                (
                    Int64($0.integer(0)), $0.text(1), $0.text(2),
                    Surface(
                        bundleIdentifier: $0.text(3), role: $0.text(4), locator: $0.text(5),
                        scope: $0.text(6))
                )
            }
            for (row, previous, next, surface) in successions
            where refuses(previous, surface) || refuses(next, surface) {
                try database.run("DELETE FROM succession WHERE rowid = ?") { $0.bind(1, row) }
            }
            try database.run(
                "INSERT INTO sweep (name, version) VALUES (?, ?) ON CONFLICT (name) DO UPDATE SET version = excluded.version",
                {
                    $0.bind(1, name)
                    $0.bind(2, Int64(version))
                })
        }
        if removed > 0 { leaveNothingBehind() }
        return removed
    }

    /// Confirms an encrypted snapshot or empties the legacy write-ahead log after a deletion.
    @discardableResult
    private func leaveNothingBehind() -> Bool {
        if database.usesEncryptedSnapshots {
            try? compactIfNeeded()
            return true
        }
        let refused = try? database.rows("PRAGMA wal_checkpoint(TRUNCATE)", { _ in }) { $0.integer(0) }
        if refused?.first == 0 { try? compactIfNeeded() }
        return refused?.first == 0
    }

    /// Compacts a substantially reduced corpus so SQLite releases its unused pages.
    private func compactIfNeeded() throws(PredictStoreError) {
        let free = try database.rows("PRAGMA freelist_count", { _ in }) { $0.integer(0) }.first ?? 0
        guard free >= Self.compactionThresholdPages else { return }
        try database.execute("VACUUM")
        if !database.usesEncryptedSnapshots {
            _ = try database.rows("PRAGMA wal_checkpoint(TRUNCATE)", { _ in }) { $0.integer(0) }
        }
    }

    /// Clears the refusals of one line in every folder of the field, since a line typed by hand is one the person wants.
    private func forgiveRefusals(of text: String, in surface: Surface) throws(PredictStoreError) {
        try database.run(
            """
            UPDATE entry SET rejected = 0
            WHERE text = ? AND rejected > 0 AND surface_id IN (
              SELECT id FROM surface WHERE bundle_id = ? AND role = ? AND locator = ?
            )
            """,
            {
                $0.bind(1, text)
                $0.bind(2, surface.bundleIdentifier)
                $0.bind(3, surface.role)
                $0.bind(4, surface.locator ?? "")
            })
    }

    // MARK: - Plumbing

    /// A tally an offer moves, closed so nothing a caller supplied can reach the statement.
    private enum Tally: String {
        case accepted
        case rejected
    }

    /// Adds one to a tally against the one entry that supplied the text, since evidence is summed across folders.
    private func increment(
        _ tally: Tally, forText text: String, in surface: Surface
    ) throws(PredictStoreError) {
        guard let entry = try supplier(of: Spelling.canonical(text), in: surface) else { return }
        let column = tally.rawValue
        try database.run("UPDATE entry SET \(column) = \(column) + 1 WHERE id = ?") { $0.bind(1, entry) }
    }

    /// The entry a read of this field would have drawn the text from, this folder's own before another folder's.
    private func supplier(of text: String, in surface: Surface) throws(PredictStoreError) -> Int64? {
        try database.rows(
            """
            SELECT entry.id FROM entry JOIN surface ON surface.id = entry.surface_id
            WHERE surface.bundle_id = ? AND surface.role = ? AND surface.locator = ? AND entry.text = ?
            ORDER BY surface.scope = ? DESC, entry.superseded_by IS NULL DESC, entry.last_used DESC
            LIMIT 1
            """,
            {
                $0.bind(1, surface.bundleIdentifier)
                $0.bind(2, surface.role)
                $0.bind(3, surface.locator ?? "")
                $0.bind(4, text)
                $0.bind(5, surface.scope ?? "")
            }
        ) { Int64($0.integer(0)) }.first
    }

    /// How many rows the fuzzy tier has looked at, which a test reads to bound the per-keystroke work.
    package static let rowsScanned = Mutex(0)
    /// Removes the least recently used scopes after a field exceeds its surface cap.
    private func evictOldestSurfaces(
        bundleIdentifier: String, role: String, locator: String, keepingSurface id: Int64
    ) throws(PredictStoreError) {
        let count =
            try database.rows(
                "SELECT COUNT(*) FROM surface WHERE bundle_id = ? AND role = ? AND locator = ?",
                {
                    $0.bind(1, bundleIdentifier); $0.bind(2, role); $0.bind(3, locator)
                }
            ) { $0.integer(0) }.first ?? 0
        guard count > Self.surfacesPerField else { return }
        let excess = count - Self.surfacesPerField
        try database.run(
            "DELETE FROM surface WHERE id IN (SELECT id FROM surface WHERE bundle_id = ? AND role = ? AND locator = ? AND id != ? ORDER BY last_used ASC, id ASC LIMIT ?)",
            {
                $0.bind(1, bundleIdentifier)
                $0.bind(2, role)
                $0.bind(3, locator)
                $0.bind(4, id)
                $0.bind(5, Int64(excess))
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
                    lastUsed: Self.clampedLastUsed(row.double(5))),
                editDistance: distance,
                isIrreversible: DestructiveCommand.matches(row.text(0), failClosedOnUnresolved: true))
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
            "INSERT INTO surface (bundle_id, role, locator, scope, last_used) VALUES (?, ?, ?, ?, 0)", bind)
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
