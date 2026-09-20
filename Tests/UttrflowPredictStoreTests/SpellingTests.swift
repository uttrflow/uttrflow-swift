// Tests that one accented line is one entry however its accent was encoded.
import Foundation
import Testing
import UttrflowPredict

@testable import UttrflowPredictStore

private let field = Surface(bundleIdentifier: "com.apple.TextEdit", role: "AXTextArea")
private let when = Date(timeIntervalSince1970: 1_800_000_000)
/// The accent as one scalar, as most keyboards type it.
private let precomposed = "caf\u{E9} au lait"
/// The accent as a letter and a combining mark, as some input methods and pastes deliver it.
private let decomposed = "cafe\u{301} au lait"

/// The raw bytes a row holds, since `==` on two strings ignores how their accents were encoded.
private func storedBytes(_ corpus: borrowing Corpus, _ sql: String) throws -> [[UInt8]] {
    let database = try Database(path: corpus.path)
    return try database.rows(sql, { _ in }) { Array($0.text(0).utf8) }
}

@Suite("One line however its accents were encoded")
struct SpellingTests {
    @Test("The two encodings of one accented line are stored as one entry, counted together.")
    func oneEntryAcrossEncodings() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record(precomposed, in: field, at: when)
        try await store.record(decomposed, in: field, at: when)
        #expect(try await store.entryCount() == 1)
        let found = try await store.candidates(for: field, matching: "caf")
        #expect(found.first?.evidence?.count == 2)
        #expect(try storedBytes(corpus, "SELECT text FROM entry") == [Array(precomposed.utf8)])
    }

    @Test(
        "A prefix typed in either encoding finds the line stored in the other.",
        arguments: [(precomposed, "cafe\u{301}"), (decomposed, "caf\u{E9}")])
    func prefixFindsTheOtherEncoding(stored: String, typed: String) async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record(stored, in: field, at: when)
        #expect(try await store.candidates(for: field, matching: typed).count == 1)
    }

    @Test("Taking, typing past, retiring and forgetting all reach the line whichever encoding names it.")
    func everyWriteFindsTheEntry() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record(precomposed, in: field, at: when)
        try await store.recordAccepted(decomposed, in: field)
        try await store.recordRejected(decomposed, in: field)
        let evidence = try await store.candidates(for: field, matching: "caf").first?.evidence
        #expect(evidence?.accepted == 1)
        #expect(evidence?.rejected == 1)
        try await store.supersede(decomposed, with: "cafe\u{301} noir", in: field)
        #expect(try await store.candidates(for: field, matching: "caf").isEmpty)
        #expect(try storedBytes(corpus, "SELECT superseded_by FROM entry") == [Array("caf\u{E9} noir".utf8)])
        try await store.forget(decomposed, in: field)
        #expect(try await store.entryCount() == 0)
    }

    @Test("What followed a line is found whichever encoding the line arrives in.")
    func successionAcrossEncodings() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record(precomposed, in: field, at: when)
        try await store.record("see you there", in: field, after: decomposed, at: when)
        let next = try await store.successors(for: field, after: precomposed)
        #expect(next.map(\.text) == ["see you there"])
    }

    @Test(
        "A file from the build before has its lines rewritten in one encoding, and duplicates folded together."
    )
    func migratesDecomposedRows() async throws {
        let corpus = Corpus()
        do {
            let old = try Database(path: corpus.path)
            try Schema.migrate(old)
            try old.run("UPDATE schema_version SET version = ?") { $0.bind(1, Int64(3)) }
            try old.run("INSERT INTO surface (bundle_id, role) VALUES (?, ?)") {
                $0.bind(1, field.bundleIdentifier)
                $0.bind(2, field.role)
            }
            let rows: [(String, Int64, String?)] = [
                (precomposed, 2, nil), (decomposed, 3, nil), ("re\u{301}sume\u{301}", 1, nil),
                ("caf", 1, decomposed),
            ]
            for (text, count, supersededBy) in rows {
                try old.run(
                    """
                    INSERT INTO entry (surface_id, text, text_lower, count, accepted, last_used, superseded_by)
                    VALUES (1, ?, ?, ?, 1, ?, ?)
                    """
                ) {
                    $0.bind(1, text)
                    $0.bind(2, text.lowercased())
                    $0.bind(3, count)
                    $0.bind(4, when.timeIntervalSince1970)
                    if let supersededBy { $0.bind(5, supersededBy) }
                }
            }
            for (previous, next, count) in [
                (precomposed, "see you there", Int64(1)), (decomposed, "see you there", 2),
                ("re\u{301}sume\u{301}", "sent", 1), ("sent", "done", 1),
            ] {
                let insert = "INSERT INTO succession (surface_id, previous, next, count) VALUES (1, ?, ?, ?)"
                try old.run(insert) {
                    $0.bind(1, previous)
                    $0.bind(2, next)
                    $0.bind(3, count)
                }
            }
        }

        let store = try store(corpus)
        #expect(try await store.entryCount() == 3)
        let cafe = try await store.candidates(for: field, matching: "cafe\u{301}").first?.evidence
        #expect(cafe?.count == 5)
        #expect(cafe?.accepted == 2)
        #expect(try await store.candidates(for: field, matching: "r\u{E9}sum").count == 1)
        #expect(
            try storedBytes(corpus, "SELECT superseded_by FROM entry WHERE superseded_by IS NOT NULL")
                == [Array(precomposed.utf8)])
        let counts = try Database(path: corpus.path).rows(
            "SELECT count FROM succession WHERE next = 'see you there'", { _ in }
        ) { $0.integer(0) }
        #expect(counts == [3])
        #expect(
            try storedBytes(corpus, "SELECT previous FROM succession WHERE next = 'sent'")
                == [Array("r\u{E9}sum\u{E9}".utf8)])
        let version = try Database(path: corpus.path).rows("SELECT version FROM schema_version", { _ in }) {
            $0.integer(0)
        }
        #expect(version == [Schema.version])
    }

    @Test("A line already in one encoding is left as it is.")
    func canonicalTextIsUnchanged() {
        #expect(Spelling.isCanonical(precomposed))
        #expect(Spelling.isCanonical(decomposed) == false)
        #expect(Array(Spelling.canonical(decomposed).utf8) == Array(precomposed.utf8))
    }
}
