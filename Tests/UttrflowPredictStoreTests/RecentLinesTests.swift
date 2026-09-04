import Foundation
import Testing
import UttrflowPredict

@testable import UttrflowPredictStore

/// A database of its own per test, removed when the test ends.
private struct Corpus: ~Copyable {
    let path: String

    init() {
        path = NSTemporaryDirectory() + "uttrflow-recent-\(UUID().uuidString).sqlite"
        remove()
    }

    func remove() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }

    deinit { remove() }
}

private let chat = Surface(bundleIdentifier: "com.example.chat", role: "AXTextArea", locator: "Message")
private let otherRoom = Surface(
    bundleIdentifier: "com.example.chat", role: "AXTextArea", locator: "Message", scope: "room-b")
private let search = Surface(bundleIdentifier: "com.example.chat", role: "AXTextField", locator: "Search")
private let moment = Date(timeIntervalSince1970: 1_800_000_000)

@Suite("The lines this person wrote here")
struct RecentLinesTests {
    @Test("The most recent lines come first, each once, and no more than were asked for.")
    func newestFirstAndDistinct() async throws {
        let corpus = Corpus()
        let store = try PredictStore(path: corpus.path)
        try await store.record("on my way", in: chat, at: moment)
        try await store.record("sounds good, see you at 7", in: chat, at: moment.addingTimeInterval(60))
        try await store.record("on my way", in: chat, at: moment.addingTimeInterval(120))
        try await store.record("running late, sorry", in: chat, at: moment.addingTimeInterval(180))
        #expect(
            try await store.recent(in: chat, limit: 6)
                == ["running late, sorry", "on my way", "sounds good, see you at 7"])
        #expect(try await store.recent(in: chat, limit: 1) == ["running late, sorry"])
        #expect(try await store.recent(in: chat, limit: 0).isEmpty)
    }

    @Test("A line marked wrong is not how this person writes, and a field never typed in has nothing.")
    func wrongLinesAndEmptyFieldsGiveNothing() async throws {
        let corpus = Corpus()
        let store = try PredictStore(path: corpus.path)
        try await store.record("teh thing", in: chat, at: moment)
        try await store.record("the thing", in: chat, at: moment.addingTimeInterval(60))
        await store.recordRejection(of: "teh thing", in: chat)
        #expect(try await store.recent(in: chat, limit: 6) == ["the thing"])
        #expect(try await store.recent(in: search, limit: 6).isEmpty)
    }

    @Test("The same field in another document is still this person writing here, so its lines count too.")
    func everyDocumentOfTheFieldCounts() async throws {
        let corpus = Corpus()
        let store = try PredictStore(path: corpus.path)
        try await store.record("see you there", in: chat, at: moment)
        try await store.record("can we move it to 8?", in: otherRoom, at: moment.addingTimeInterval(60))
        #expect(try await store.recent(in: chat, limit: 6) == ["can we move it to 8?", "see you there"])
    }
}
