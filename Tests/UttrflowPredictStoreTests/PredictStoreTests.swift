import Foundation
import Testing
import UttrflowPredict

@testable import UttrflowPredictStore

/// A database of its own per test, removed when the test ends.
private struct Corpus: ~Copyable {
    let path: String

    init(_ name: String = UUID().uuidString) {
        path = NSTemporaryDirectory() + "uttrflow-predict-\(name).sqlite"
        remove()
    }

    func remove() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }

    deinit { remove() }
}

private let terminal = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea")
private let moment = Date(timeIntervalSince1970: 1_800_000_000)

/// Opens a store on a fresh file, so each test starts from nothing.
private func store(_ corpus: borrowing Corpus) throws -> PredictStore {
    try PredictStore(path: corpus.path)
}

@Suite("Remembering what was entered")
struct RecordingTests {
    @Test("What was entered comes back when its opening is typed.")
    func roundTrip() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git commit -m", in: terminal, at: moment)
        let found = try await store.candidates(for: terminal, matching: "git c")
        #expect(found.map(\.text) == ["git commit -m"])
        #expect(found.first?.evidence?.count == 1)
    }

    @Test("Entering the same thing twice counts twice rather than storing it twice.")
    func countsRepeats() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        for _ in 0..<3 { try await store.record("make verify", in: terminal, at: moment) }
        let found = try await store.candidates(for: terminal, matching: "make")
        #expect(found.count == 1)
        #expect(found.first?.evidence?.count == 3)
    }

    @Test("An empty value is not worth remembering.")
    func ignoresEmpty() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("", in: terminal, at: moment)
        #expect(try await store.entryCount() == 0)
    }

    @Test("A fragment left behind by an idle is not stored once the whole line it belongs to is known.")
    func fragmentOfALongerLineIsNotStored() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git status", in: terminal, at: moment)
        try await store.record("git statu", in: terminal, at: moment)
        try await store.record("gi", in: terminal, at: moment)
        #expect(try await store.candidates(for: terminal, matching: "gi").map(\.text) == ["git status"])
    }

    @Test("A longer line retires the fragments it grew out of, so only the whole value is offered.")
    func longerLineSupersedesItsFragments() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git statu", in: terminal, at: moment)
        try await store.record("git status", in: terminal, at: moment)
        #expect(try await store.candidates(for: terminal, matching: "git s").map(\.text) == ["git status"])
    }

    @Test("Prefix hygiene ignores case, so a capitalised fragment is still recognised as one.")
    func fragmentSuppressionIgnoresCase() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("Git Status", in: terminal, at: moment)
        try await store.record("git st", in: terminal, at: moment)
        #expect(try await store.candidates(for: terminal, matching: "git").map(\.text) == ["Git Status"])
    }

    @Test("A line that only shares an opening is not a fragment, so both are kept.")
    func siblingsAreBothKept() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git push", in: terminal, at: moment)
        try await store.record("git pull", in: terminal, at: moment)
        #expect(try await store.candidates(for: terminal, matching: "git p").count == 2)
    }

    @Test("Nothing typed means nothing offered, because everything would match.")
    func emptyQueryOffersNothing() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("make verify", in: terminal, at: moment)
        #expect(try await store.candidates(for: terminal, matching: "").isEmpty)
    }

    @Test("A field never typed in has nothing to say, and is not created by asking.")
    func unknownSurfaceIsNotCreated() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let elsewhere = Surface(bundleIdentifier: "com.example.other", role: "AXTextField")
        #expect(try await store.candidates(for: elsewhere, matching: "git").isEmpty)
        #expect(try await store.successors(for: elsewhere, after: "x").isEmpty)
    }

    @Test("Two fields in one application keep their own memories.")
    func surfacesAreSeparate() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let omnibox = Surface(
            bundleIdentifier: "com.example.browser", role: "AXTextField", locator: "omnibox")
        let search = Surface(bundleIdentifier: "com.example.browser", role: "AXTextField", locator: "search")
        try await store.record("example.com/dashboard", in: omnibox, at: moment)
        #expect(try await store.candidates(for: search, matching: "example").isEmpty)
        #expect(try await store.candidates(for: omnibox, matching: "example").count == 1)
    }

    @Test("The same field in two directories shares what was learned, not walled off by its folder.")
    func scopeDoesNotSeparate() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let here = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "~/one")
        let there = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "~/two")
        try await store.record("swift build", in: here, at: moment)
        #expect(try await store.candidates(for: there, matching: "swift").count == 1)
    }

    @Test("A phrase entered in two directories is one candidate, its counts summed across both.")
    func scopesMergeIntoOne() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let here = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "~/one")
        let there = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "~/two")
        try await store.record("swift build", in: here, at: moment)
        try await store.record("swift build", in: there, at: moment)
        try await store.record("swift build", in: there, at: moment)
        let found = try await store.candidates(for: here, matching: "swift")
        #expect(found.count == 1)
        #expect(found.first?.evidence?.count == 3)
    }

    @Test("A suggestion taken rather than typed is recorded as ours, so it counts for less.")
    func selfSourcedIsMarked() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git status", in: terminal, selfSourced: true, at: moment)
        let found = try await store.candidates(for: terminal, matching: "git s")
        #expect(found.first?.evidence?.selfSourced == 1)
    }

    @Test("Being offered and taken, or offered and refused, is counted either way.")
    func offersAreCounted() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("npm run dev", in: terminal, at: moment)
        try await store.recordAccepted("npm run dev", in: terminal)
        try await store.recordRejected("npm run dev", in: terminal)
        try await store.recordRejected("npm run dev", in: terminal)
        let found = try await store.candidates(for: terminal, matching: "npm")
        #expect(found.first?.evidence?.accepted == 1)
        #expect(found.first?.evidence?.rejected == 2)
    }

    @Test("Counting an offer against something never entered changes nothing and does not fail.")
    func offerAgainstUnknown() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.recordAccepted("never typed", in: terminal)
        #expect(try await store.entryCount() == 0)
    }
}

@Suite("What usually follows what")
struct SuccessionTests {
    @Test("A command that followed another is offered when that one has just run.")
    func remembersOrder() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git add .", in: terminal, at: moment)
        try await store.record("git commit -m", in: terminal, after: "git add .", at: moment)
        let next = try await store.successors(for: terminal, after: "git add .")
        #expect(next.map(\.text) == ["git commit -m"])
        #expect(next.first?.source == .succession)
    }

    @Test("The more often one follows another, the higher it comes.")
    func ordersByHowOften() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git push", in: terminal, after: "git commit -m", at: moment)
        for _ in 0..<4 {
            try await store.record("make verify", in: terminal, after: "git commit -m", at: moment)
        }
        let next = try await store.successors(for: terminal, after: "git commit -m")
        #expect(next.first?.text == "make verify")
    }

    @Test("Nothing followed nothing, so an empty predecessor is not recorded.")
    func emptyPredecessorIsIgnored() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git status", in: terminal, after: "", at: moment)
        #expect(try await store.successors(for: terminal, after: "").isEmpty)
    }

    @Test("A successor that has since been forgotten is not offered.")
    func forgottenSuccessorIsDropped() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git add .", in: terminal, at: moment)
        try await store.record("git commit -m", in: terminal, after: "git add .", at: moment)
        try await store.forget("git commit -m", in: terminal)
        #expect(try await store.successors(for: terminal, after: "git add .").isEmpty)
    }
}

@Suite("Matching what was nearly typed")
struct StoreMatchingTests {
    @Test("A transposed command is found when nothing matches exactly.")
    func fuzzyRescuesATypo() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git commit -m", in: terminal, at: moment)
        let found = try await store.candidates(for: terminal, matching: "gti c")
        #expect(found.map(\.text) == ["git commit -m"])
        #expect(found.first?.editDistance == 1)
    }

    @Test("A query that matches exactly never reaches the fuzzy tier, so its neighbours stay out.")
    func exactSuppressesFuzzy() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git push", in: terminal, at: moment)
        try await store.record("git commit -m", in: terminal, at: moment)
        let found = try await store.candidates(for: terminal, matching: "git p")
        #expect(found.map(\.text) == ["git push"])
    }

    @Test("Two characters are too few to correct, or everything would match.")
    func shortQueriesAreNotCorrected() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git commit -m", in: terminal, at: moment)
        #expect(try await store.candidates(for: terminal, matching: "gt").isEmpty)
    }

    @Test("An entry found to be wrong is never offered again, exactly or otherwise.")
    func supersededIsNeverOffered() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git comit", in: terminal, at: moment)
        try await store.supersede("git comit", with: "git commit", in: terminal)
        #expect(try await store.candidates(for: terminal, matching: "git c").isEmpty)
        #expect(try await store.candidates(for: terminal, matching: "gti c").isEmpty)
    }

    @Test("Superseding something in a field never typed in changes nothing.")
    func supersedeUnknownSurface() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.supersede("a", with: "b", in: terminal)
        #expect(try await store.entryCount() == 0)
    }

    @Test("The prefix range ends where the next letter begins.")
    func upperBound() {
        #expect(PredictStore.upperBound(of: "git c") == "git d")
        #expect(PredictStore.upperBound(of: "a") == "b")
        #expect(PredictStore.upperBound(of: "") == nil)
    }
}

@Suite("Forgetting")
struct ForgettingTests {
    @Test("One entry can be forgotten without touching the rest.")
    func oneEntry() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git push", in: terminal, at: moment)
        try await store.record("git pull", in: terminal, at: moment)
        try await store.forget("git push", in: terminal)
        #expect(try await store.candidates(for: terminal, matching: "git p").map(\.text) == ["git pull"])
    }

    @Test("Everything learned in one application goes together, and other applications stay.")
    func oneApplication() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let elsewhere = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea")
        try await store.record("git push", in: terminal, at: moment)
        try await store.record("some prose", in: elsewhere, at: moment)
        try await store.forget(bundleIdentifier: "com.example.terminal")
        #expect(try await store.entryCount() == 1)
        #expect(try await store.candidates(for: elsewhere, matching: "some").count == 1)
    }

    @Test("The reset in Settings leaves nothing behind.")
    func everything() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git push", in: terminal, at: moment)
        try await store.forgetEverything()
        #expect(try await store.entryCount() == 0)
    }

    @Test("Forgetting from a field never typed in is not an error.")
    func unknownSurface() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.forget("anything", in: terminal)
        #expect(try await store.entryCount() == 0)
    }
}

@Suite("Staying within bounds")
struct RetentionTests {
    @Test("A field stops growing at its cap, and drops what has least behind it.")
    func evictsWeakest() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let kept = "kept command"
        for _ in 0..<5 { try await store.record(kept, in: terminal, at: moment) }
        for index in 0..<(PredictStore.entriesPerSurface + 20) {
            try await store.record("filler \(index)", in: terminal, at: moment)
        }
        #expect(try await store.entryCount() <= PredictStore.entriesPerSurface)
        #expect(try await store.candidates(for: terminal, matching: "kept").count == 1)
    }

    @Test("A superseded entry goes before any live one, however much it once had behind it.")
    func evictsSupersededFirst() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        for _ in 0..<50 { try await store.record("git comit", in: terminal, at: moment) }
        try await store.supersede("git comit", with: "git commit", in: terminal)
        // Each filler ends in a word so none is a fragment of another, which would supersede it too.
        for index in 0..<(PredictStore.entriesPerSurface + 1) {
            try await store.record("filler \(index) end", in: terminal, at: moment)
        }
        let superseded = try Database(path: corpus.path).rows(
            "SELECT COUNT(*) FROM entry WHERE superseded_by IS NOT NULL", { _ in }
        ) { $0.integer(0) }
        #expect(superseded == [0])
        #expect(try await store.entryCount() == PredictStore.entriesPerSurface)
    }
}

@Suite("Writing all of a record or none of it")
struct TransactionTests {
    @Test("A step that fails takes the steps before it back with it.")
    func failureRollsBack() throws {
        let corpus = Corpus()
        let database = try Database(path: corpus.path)
        try Schema.migrate(database)
        #expect(throws: PredictStoreError.self) {
            try database.transaction { () throws(PredictStoreError) in
                try database.run("INSERT INTO surface (bundle_id, role) VALUES ('com.example.app', 'AXTextArea')") {
                    _ in
                }
                try database.execute("SELECT FROM WHERE")
            }
        }
        #expect(try database.rows("SELECT COUNT(*) FROM surface", { _ in }) { $0.integer(0) } == [0])
        #expect(try database.rows("SELECT 1", { _ in }) { $0.integer(0) } == [1])
    }

    @Test("A record that goes through is there for another connection to read.")
    func successCommits() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git push", in: terminal, after: "git commit", at: moment)
        let other = try Database(path: corpus.path)
        #expect(try other.rows("SELECT COUNT(*) FROM entry", { _ in }) { $0.integer(0) } == [1])
        #expect(try other.rows("SELECT COUNT(*) FROM succession", { _ in }) { $0.integer(0) } == [1])
    }
}

@Suite("Surviving a broken file")
struct RecoveryTests {
    @Test("A file that is not a database is replaced rather than crashing the app.")
    func replacesRubbish() async throws {
        let corpus = Corpus()
        try Data("this is not a database, it is a haiku".utf8).write(to: URL(fileURLWithPath: corpus.path))
        let store = try store(corpus)
        try await store.record("git push", in: terminal, at: moment)
        #expect(try await store.entryCount() == 1)
    }

    @Test("A database written by a newer build is refused and left exactly as it was, not replaced.")
    func refusesTheFuture() throws {
        let corpus = Corpus()
        let database = try Database(path: corpus.path)
        try Schema.migrate(database)
        try database.run("UPDATE schema_version SET version = ?") { $0.bind(1, Int64(99)) }
        try database.run("INSERT INTO surface (bundle_id, role) VALUES ('com.example.app', 'AXTextArea')") {
            _ in
        }
        #expect(throws: PredictStoreError.newerThanThisBuild(version: 99)) {
            try PredictStore(path: corpus.path)
        }
        let version = try database.rows("SELECT version FROM schema_version", { _ in }) { $0.integer(0) }
        #expect(version == [99])
        #expect(try database.rows("SELECT COUNT(*) FROM surface", { _ in }) { $0.integer(0) } == [1])
    }

    @Test("A file from the build before gains the recency index and the current version on opening.")
    func migratesFromVersionTwo() throws {
        let corpus = Corpus()
        let database = try Database(path: corpus.path)
        try Schema.migrate(database)
        try database.execute("DROP INDEX entry_recent")
        try database.run("UPDATE schema_version SET version = ?") { $0.bind(1, Int64(2)) }
        try Schema.migrate(database)
        let indexes = try database.rows("PRAGMA index_list(entry)", { _ in }) { $0.text(1) }
        #expect(indexes.contains("entry_recent"))
        let version = try database.rows("SELECT version FROM schema_version", { _ in }) { $0.integer(0) }
        #expect(version == [Schema.version])
    }

    @Test("A path that cannot be opened at all is reported rather than pretended about.")
    func reportsAnImpossiblePath() {
        #expect(throws: PredictStoreError.self) {
            try PredictStore(path: "/this/directory/does/not/exist/corpus.sqlite")
        }
    }

    @Test("A statement that is not SQL is reported as a query failure.")
    func reportsABadStatement() throws {
        let corpus = Corpus()
        let database = try Database(path: corpus.path)
        #expect(throws: PredictStoreError.self) { try database.execute("SELECT FROM WHERE") }
    }
}

@Suite("The query that runs on every keystroke")
struct QueryPlanTests {
    /// Fills a database directly, because the point is the plan and not the round trips.
    private func seed(_ path: String, surfaces: Int, each: Int) throws {
        let database = try Database(path: path)
        try Schema.migrate(database)
        try database.execute("BEGIN")
        for surface in 0..<surfaces {
            try database.run(
                "INSERT INTO surface (bundle_id, role, locator, scope) VALUES (?, ?, '', '')"
            ) {
                $0.bind(1, "com.example.app\(surface)")
                $0.bind(2, "AXTextArea")
            }
            let id = database.lastInsertedIdentifier
            for index in 0..<each {
                try database.run(
                    "INSERT INTO entry (surface_id, text, text_lower, count, last_used) VALUES (?, ?, ?, ?, ?)"
                ) {
                    $0.bind(1, id)
                    $0.bind(2, "git command \(index) --flag=\(index)")
                    $0.bind(3, "git command \(index) --flag=\(index)")
                    $0.bind(4, Int64(index % 40 + 1))
                    $0.bind(5, moment.timeIntervalSince1970)
                }
            }
        }
        try database.execute("COMMIT")
    }

    @Test("The prefix query narrows on the text as well as the field, which is the whole point of the index.")
    func usesBothIndexColumns() throws {
        let corpus = Corpus()
        try seed(corpus.path, surfaces: 4, each: 500)
        let database = try Database(path: corpus.path)
        let plan = try database.plan(of: PredictStore.prefixQuery).joined(separator: " | ")
        #expect(plan.contains("USING INDEX entry_prefix"), "the plan was: \(plan)")
        #expect(plan.contains("text_lower>?"), "the plan was: \(plan)")
        #expect(!plan.contains("SCAN entry"), "the plan was: \(plan)")
    }

    @Test("The recency read has an index of its own, so it does not walk the field's rows by hand.")
    func recentReadUsesItsIndex() throws {
        let corpus = Corpus()
        try seed(corpus.path, surfaces: 4, each: 500)
        let database = try Database(path: corpus.path)
        let plan = try database.plan(of: PredictStore.recentQuery(surfaces: 2)).joined(separator: " | ")
        #expect(plan.contains("USING INDEX entry_recent"), "the plan was: \(plan)")
        #expect(!plan.contains("SCAN entry"), "the plan was: \(plan)")
    }

    @Test(
        "Written as a LIKE the same query reads every row of the field, which is why it is not written that way."
    )
    func likeReadsTheWholeSurface() throws {
        let corpus = Corpus()
        try seed(corpus.path, surfaces: 4, each: 500)
        let database = try Database(path: corpus.path)
        let asLike = """
            SELECT text FROM entry
            WHERE surface_id = ? AND text LIKE ? AND superseded_by IS NULL
            ORDER BY count DESC LIMIT ?
            """
        let plan = try database.plan(of: asLike).joined(separator: " | ")
        #expect(!plan.contains("text_lower>?"), "LIKE unexpectedly narrowed the text: \(plan)")
    }

    @Test("A query against twenty thousand entries still returns only what was asked for.")
    func staysBoundedAtScale() async throws {
        let corpus = Corpus()
        try seed(corpus.path, surfaces: 10, each: 2_000)
        let store = try PredictStore(path: corpus.path)
        let surface = Surface(bundleIdentifier: "com.example.app3", role: "AXTextArea")
        let found = try await store.candidates(for: surface, matching: "git command 1")
        #expect(found.count <= PredictStore.candidateLimit)
        #expect(found.allSatisfy { $0.text.hasPrefix("git command 1") })
    }
}

@Suite("Superseding through the verification tier")
struct StoreSupersessionTests {
    @Test("What the gates corrected is superseded here without them having anywhere to report a failure.")
    func recordsThroughTheProtocol() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git comit", in: terminal, at: moment)
        let recording: any SupersessionRecording = store
        await recording.recordSupersession(of: "git comit", by: "git commit", in: terminal)
        #expect(try await store.candidates(for: terminal, matching: "git c").isEmpty)
    }

    @Test("What the gates refused is put out of reach here, with nothing named as replacing it.")
    func recordsARejection() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git zqxjw", in: terminal, at: moment)
        let recording: any SupersessionRecording = store
        await recording.recordRejection(of: "git zqxjw", in: terminal)
        #expect(try await store.candidates(for: terminal, matching: "git z").isEmpty)
    }
}

@Suite("Where the corpus lives")
struct PredictStoreLocationTests {
    @Test("It sits in Uttrflow's own folder, versioned in its name.")
    func inTheAppsOwnFolder() {
        let file = PredictStore.defaultFile(in: URL(filePath: "/tmp/support"))
        #expect(file.path(percentEncoded: false) == "/tmp/support/Uttrflow/predict.v1.sqlite")
    }

    @Test("A folder that does not exist yet is made rather than refused.")
    func makesItsOwnFolder() throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = PredictStore.defaultFile(in: root)
        _ = try PredictStore(path: file.path(percentEncoded: false))
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }
}
