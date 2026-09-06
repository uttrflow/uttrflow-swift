import Foundation
import Testing
import UttrflowPredict

@testable import UttrflowPredictStore

private struct CaseCorpus: ~Copyable {
    let path: String
    init(_ name: String = UUID().uuidString) {
        path = NSTemporaryDirectory() + "uttrflow-case-\(name).sqlite"
        remove()
    }
    func remove() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }
    deinit { remove() }
}

private let field = Surface(bundleIdentifier: "com.apple.TextEdit", role: "AXTextArea")
private let when = Date(timeIntervalSince1970: 1_800_000_000)

@Suite("Matching ignores case but preserves it")
struct CaseMatchingTests {
    @Test("A capitalised query matches a lowercased entry, which is what auto-capitalisation causes.")
    func capitalisedQueryMatchesLowercasedEntry() async throws {
        let corpus = CaseCorpus()
        let store = try PredictStore(path: corpus.path)
        try await store.record("restart the staging database", in: field, at: when)
        let found = try await store.candidates(for: field, matching: "Restart the")
        #expect(found.map(\.text) == ["restart the staging database"])
    }

    @Test("The suggestion keeps the casing that was stored, not the casing that was typed.")
    func preservesStoredCasing() async throws {
        let corpus = CaseCorpus()
        let store = try PredictStore(path: corpus.path)
        try await store.record("GitHub Actions", in: field, at: when)
        let found = try await store.candidates(for: field, matching: "github")
        #expect(found.first?.text == "GitHub Actions")
    }

    @Test("A near-typed match is found across a case difference in the fuzzy tier too.")
    func fuzzyMatchesAcrossCase() async throws {
        let corpus = CaseCorpus()
        let store = try PredictStore(path: corpus.path)
        try await store.record("git commit -m", in: field, at: when)
        // Capitalised and transposed: only the fuzzy tier can rescue it, and only if it folds case.
        let found = try await store.candidates(for: field, matching: "Gti c")
        #expect(found.map(\.text) == ["git commit -m"])
    }

    @Test("A v1 file with no lowercased column is migrated and then matches without regard to case.")
    func migratesAnExistingVersionOneFile() async throws {
        let corpus = CaseCorpus()
        // Build the old v1 shape by hand: a text column, no text_lower, the index over text.
        let old = try Database(path: corpus.path)
        try old.execute("CREATE TABLE schema_version (version INTEGER NOT NULL)")
        try old.execute(
            """
            CREATE TABLE surface (
              id INTEGER PRIMARY KEY, bundle_id TEXT NOT NULL, role TEXT NOT NULL,
              locator TEXT NOT NULL DEFAULT '', scope TEXT NOT NULL DEFAULT '',
              UNIQUE (bundle_id, role, locator, scope))
            """)
        try old.execute(
            """
            CREATE TABLE entry (
              id INTEGER PRIMARY KEY, surface_id INTEGER NOT NULL, text TEXT NOT NULL,
              count INTEGER NOT NULL DEFAULT 1, accepted INTEGER NOT NULL DEFAULT 0,
              rejected INTEGER NOT NULL DEFAULT 0, self_sourced INTEGER NOT NULL DEFAULT 0,
              last_used REAL NOT NULL, superseded_by TEXT, UNIQUE (surface_id, text))
            """)
        try old.execute("CREATE INDEX entry_prefix ON entry (surface_id, text)")
        try old.run("INSERT INTO schema_version (version) VALUES (1)") { _ in }
        try old.run("INSERT INTO surface (bundle_id, role) VALUES (?, ?)") {
            $0.bind(1, field.bundleIdentifier)
            $0.bind(2, field.role)
        }
        try old.run("INSERT INTO entry (surface_id, text, last_used) VALUES (1, ?, ?)") {
            $0.bind(1, "restart the staging database")
            $0.bind(2, when.timeIntervalSince1970)
        }

        // Reopening runs the migration; the capitalised query must now find the lowercased entry.
        let store = try PredictStore(path: corpus.path)
        let found = try await store.candidates(for: field, matching: "Restart the")
        #expect(found.map(\.text) == ["restart the staging database"])
    }

    @Test("The lowercased and the original casing are one entry, counted together, not two.")
    func oneEntryAcrossCasesWhenIdentical() async throws {
        let corpus = CaseCorpus()
        let store = try PredictStore(path: corpus.path)
        try await store.record("make verify", in: field, at: when)
        try await store.record("make verify", in: field, at: when)
        let found = try await store.candidates(for: field, matching: "MAKE")
        #expect(found.count == 1)
        #expect(found.first?.evidence?.count == 2)
    }
}
