import Foundation
import Testing
import UttrflowPredict

@testable import UttrflowPredictStore

/// A database of its own per test, removed when the test ends.
private struct Bench: ~Copyable {
    let path: String

    init(_ name: String = UUID().uuidString) {
        path = NSTemporaryDirectory() + "uttrflow-draw-\(name).sqlite"
        remove()
    }

    func remove() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }

    deinit { remove() }
}

private let editor = Surface(bundleIdentifier: "com.apple.TextEdit", role: "AXTextArea")

/// The real store feeding the real engine, which is the path a keystroke actually takes.
@Suite("A learned line is drawn when a prefix of it is typed")
struct DrawRegressionTests {
    private func drawn(
        for typed: String, in store: PredictStore, now: Date
    ) async throws -> Suggestion {
        let candidates = try await store.candidates(for: editor, matching: typed)
        return PredictionEngine.suggestion(
            from: candidates, in: PredictionContext(typed: typed), now: now)
    }

    @Test("A line learned once is drawn from the moment its opening is typed.")
    func aFreshlyLearnedLineDraws() async throws {
        let bench = Bench()
        let store = try PredictStore(path: bench.path)
        let now = Date()
        try await store.record("restart the staging database and clear the cache", in: editor, at: now)

        let suggestion = try await drawn(for: "restart the s", in: store, now: now)
        #expect(suggestion.accepting == "restart the staging database and clear the cache")
    }

    @Test("A capitalised prefix draws it too, as a real auto-capitalising field produces.")
    func aCapitalisedPrefixDraws() async throws {
        let bench = Bench()
        let store = try PredictStore(path: bench.path)
        let now = Date()
        try await store.record("restart the staging database", in: editor, at: now)

        let suggestion = try await drawn(for: "Restart the s", in: store, now: now)
        #expect(suggestion.accepting == "restart the staging database")
    }

    @Test("A near-typed prefix is rescued by the fuzzy tier and still drawn.")
    func aFuzzyPrefixDraws() async throws {
        let bench = Bench()
        let store = try PredictStore(path: bench.path)
        let now = Date()
        try await store.record("restart the staging database", in: editor, at: now)

        // Transposed and capitalised: the exact scan misses, the fuzzy tier must catch it.
        let suggestion = try await drawn(for: "Restrat the s", in: store, now: now)
        #expect(suggestion.accepting == "restart the staging database")
    }

    @Test("A line learned once and left for a week is still drawn, not decayed into silence.")
    func aWeekOldLineStillDraws() async throws {
        let bench = Bench()
        let store = try PredictStore(path: bench.path)
        let now = Date()
        let aWeekAgo = now.addingTimeInterval(-7 * 86_400)
        try await store.record("deploy to production", in: editor, at: aWeekAgo)

        let suggestion = try await drawn(for: "deploy to", in: store, now: now)
        #expect(suggestion.accepting == "deploy to production")
    }
}
