// Tests that what was forgotten is not still readable in the files beside the database (#642).
import CryptoKit
import Foundation
import Testing
import UttrflowCore
import UttrflowPredict

@testable import UttrflowPredictStore

@Suite("What is left on disk after forgetting", .serialized)
struct ForgettingLeavesNothingTests {
    static let moment = Date(timeIntervalSince1970: 1_800_000_000)
    static let marker = "zqxjvwmarker"

    static func surface(_ scope: String = "/work") -> Surface {
        Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: scope)
    }

    /// Every byte the store has written, database and write-ahead log alike, while it is still open.
    private func bytesOnDisk(_ path: String) -> Data {
        ["", "-wal"].reduce(into: Data()) { bytes, suffix in
            bytes.append((try? Data(contentsOf: URL(filePath: path + suffix))) ?? Data())
        }
    }

    private func taught(_ store: PredictStore, lines: Int) async throws {
        for line in 1...lines {
            try await store.record(
                "git commit -m \(Self.marker) \(line)", in: Self.surface(), at: Self.moment)
        }
    }

    @Test("forgetting one application leaves none of its lines in the database or the log")
    func forgettingAnApplicationLeavesNothing() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await taught(store, lines: 50)
        #expect(bytesOnDisk(corpus.path).contains(Data(Self.marker.utf8)))

        try await store.forget(bundleIdentifier: "com.example.terminal")

        #expect(!bytesOnDisk(corpus.path).contains(Data(Self.marker.utf8)))
    }

    @Test("forgetting one line leaves none of it in the database or the log")
    func forgettingOneLineLeavesNothing() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await taught(store, lines: 50)

        for line in 1...50 {
            try await store.forget("git commit -m \(Self.marker) \(line)", in: Self.surface())
        }

        #expect(!bytesOnDisk(corpus.path).contains(Data(Self.marker.utf8)))
    }

    @Test("forgetting everything leaves none of it in the database or the log")
    func forgettingEverythingLeavesNothing() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await taught(store, lines: 50)

        try await store.forgetEverything()

        #expect(!bytesOnDisk(corpus.path).contains(Data(Self.marker.utf8)))
    }

    @Test("a line forgotten in one folder stays withheld there while another folder still holds it")
    func forgottenLineStaysWithheldWithoutBeingKept() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let line = "git push \(Self.marker)"
        try await store.record(line, in: Self.surface("/one"), at: Self.moment)
        try await store.record(line, in: Self.surface("/two"), at: Self.moment)

        try await store.forget(line, in: Self.surface("/one"))

        #expect(try await store.candidates(for: Self.surface("/one"), matching: "git p").isEmpty)
        #expect(try await store.recent(in: Self.surface("/one"), limit: 5).isEmpty)
        #expect(
            try await store.candidates(for: Self.surface("/two"), matching: "git p").map(\.text) == [line])
        let reopened = try PredictStore(path: corpus.path)
        #expect(try await reopened.candidates(for: Self.surface("/one"), matching: "git p").isEmpty)
    }

    @Test("accepting a forgotten line stores nothing, and typing it by hand brings it back")
    func forgottenLineReturnsOnlyByHand() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let line = "git push \(Self.marker)"
        try await store.record(line, in: Self.surface(), at: Self.moment)
        try await store.forget(line, in: Self.surface())

        try await store.record(line, in: Self.surface(), selfSourced: true, at: Self.moment)
        #expect(try await store.candidates(for: Self.surface(), matching: "git p").isEmpty)
        #expect(!bytesOnDisk(corpus.path).contains(Data(Self.marker.utf8)))

        try await store.record(line, in: Self.surface(), at: Self.moment)
        #expect(try await store.candidates(for: Self.surface(), matching: "git p").map(\.text) == [line])
    }

    @Test("a line forgotten under the shared encryption key stays forgotten after reopening")
    func forgottenUnderTheSharedKey() async throws {
        let corpus = Corpus()
        let keys = EncryptedStore(keys: FixedKeys(value: SymmetricKey(size: .bits256)))
        let store = try PredictStore(path: corpus.path, encryptedStore: keys)
        let line = "git push \(Self.marker)"
        try await store.record(line, in: Self.surface("/one"), at: Self.moment)
        try await store.record(line, in: Self.surface("/two"), at: Self.moment)

        try await store.forget(line, in: Self.surface("/one"))

        let reopened = try PredictStore(path: corpus.path, encryptedStore: keys)
        #expect(try await reopened.candidates(for: Self.surface("/one"), matching: "git p").isEmpty)
        #expect(
            try await reopened.candidates(for: Self.surface("/two"), matching: "git p").map(\.text) == [line])
    }

    @Test("a line forgotten before markers were digests is digested on first load and stays forgotten")
    func olderForgottenLinesAreMigrated() async throws {
        let corpus = Corpus()
        let line = "git push \(Self.marker)"
        do {
            let store = try store(corpus)
            try await store.record(line, in: Self.surface("/one"), at: Self.moment)
            try await store.record(line, in: Self.surface("/two"), at: Self.moment)
        }
        do {
            // The shape an earlier build left: the forgotten line kept in full as its own successor.
            let old = try Database(path: corpus.path)
            try old.run(
                "UPDATE entry SET count = 0, last_used = 0, superseded_by = text WHERE surface_id = 1"
            ) { _ in }
            try old.run("UPDATE schema_version SET version = 6") { _ in }
        }

        let store = try store(corpus)

        #expect(try await store.candidates(for: Self.surface("/one"), matching: "git p").isEmpty)
        #expect(
            try await store.candidates(for: Self.surface("/two"), matching: "git p").map(\.text) == [line])
        try await store.forget(line, in: Self.surface("/two"))
        #expect(!bytesOnDisk(corpus.path).contains(Data(Self.marker.utf8)))
    }
}

private struct FixedKeys: StoreKeyProviding {
    let value: SymmetricKey
    func key(createIfMissing _: Bool) throws -> SymmetricKey { value }
}
