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

    @Test("The same field in two directories answers differently.")
    func scopeSeparates() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let here = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "~/one")
        let there = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "~/two")
        try await store.record("swift build", in: here, at: moment)
        #expect(try await store.candidates(for: there, matching: "swift").isEmpty)
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

    @Test("A database written by a newer build is not written to by this one.")
    func refusesTheFuture() throws {
        let corpus = Corpus()
        let database = try Database(path: corpus.path)
        try Schema.migrate(database)
        try database.run("UPDATE schema_version SET version = ?") { $0.bind(1, Int64(99)) }
        #expect(throws: PredictStoreError.corrupt) { try Schema.migrate(database) }
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
struct PerformanceTests {
    /// Fills a database directly, because twenty thousand round trips through the actor is not the point.
    private func seed(_ path: String, surfaces: Int, each: Int) throws {
        let database = try Database(path: path)
        try Schema.migrate(database)
        try database.execute("BEGIN")
        for surface in 0..<surfaces {
            try database.run("INSERT INTO surface (bundle_id, role, locator, scope) VALUES (?, ?, '', '')") {
                $0.bind(1, "com.example.app\(surface)")
                $0.bind(2, "AXTextArea")
            }
            let id = database.lastInsertedIdentifier
            for index in 0..<each {
                try database.run(
                    "INSERT INTO entry (surface_id, text, count, last_used) VALUES (?, ?, ?, ?)"
                ) {
                    $0.bind(1, id)
                    $0.bind(2, "git command \(index) --flag=\(index)")
                    $0.bind(3, Int64(index % 40 + 1))
                    $0.bind(4, moment.timeIntervalSince1970)
                }
            }
        }
        try database.execute("COMMIT")
    }

    @Test("A prefix query stays under the budget with twenty thousand entries behind it.")
    func prefixQueryIsFast() async throws {
        let corpus = Corpus()
        try seed(corpus.path, surfaces: 10, each: 2_000)
        let store = try store(corpus)
        let surface = Surface(bundleIdentifier: "com.example.app3", role: "AXTextArea")

        for _ in 0..<20 { _ = try await store.candidates(for: surface, matching: "git command 1") }

        var timings: [Double] = []
        for _ in 0..<200 {
            let started = DispatchTime.now().uptimeNanoseconds
            _ = try await store.candidates(for: surface, matching: "git command 1")
            timings.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1000)
        }
        timings.sort()
        let p95 = timings[Int(Double(timings.count) * 0.95)]
        #expect(p95 < 200, "prefix query p95 was \(p95) µs, which is over the budget")
    }
}
