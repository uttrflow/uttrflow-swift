// Tests that what was forgotten is not still readable in the files beside the database (#642).
import Foundation
import Testing
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
}
