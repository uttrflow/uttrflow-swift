import Foundation
import Testing
import UttrflowContext
import UttrflowPredict
import UttrflowTestSupport

@testable import Uttrflow
@testable import UttrflowPredictStore

private enum SituationTaskMarker {
    @TaskLocal static var value: Int?
}

private final class SituationCorpus: Sendable {
    let directory: URL
    let store: PredictStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "situation-\(UUID().uuidString)")
        store = try PredictStore(path: directory.appending(path: "corpus.sqlite").path(percentEncoded: false))
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

private actor SituationWindow {
    private(set) var reads = 0
    private(set) var markers: [Int?] = []
    private(set) var wasCancelled = false
    private var continuation: CheckedContinuation<Surroundings?, Never>?

    func read(_ answer: Surroundings?) -> Surroundings? {
        reads += 1
        return answer
    }

    func heldRead() async -> Surroundings? {
        reads += 1
        markers.append(SituationTaskMarker.value)
        let answer = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation = $0 }
        } onCancel: {
            Task { await self.cancel() }
        }
        markers.append(SituationTaskMarker.value)
        wasCancelled = Task.isCancelled
        return answer
    }

    private func cancel() {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}

private func breakSituationCorpus(_ store: isolated PredictStore) throws {
    try store.database.execute("DROP TABLE surface")
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SuggestionSituationBuilderTests {
    private static func log(_: Surroundings?, _: [String], _: GenerationSituation) {}
    private static let around = Surroundings(windowTitle: "Notes", text: "a page of words", timedTurnLines: 2)

    private static func snapshot(
        bundle: String = "com.example.notes", window: UInt32 = 7
    ) -> FocusedFieldSnapshot {
        FocusedFieldSnapshot(
            bundleIdentifier: bundle, applicationName: "Notes", role: "AXTextArea",
            value: "before\ncurrent", selection: NSRange(location: 14, length: 0),
            windowTitle: "Notes", windowNumber: window)
    }

    private static func query(_ snapshot: FocusedFieldSnapshot, typed: String = "current") -> SuggestionQuery
    {
        SuggestionQuery(
            surface: Surface(bundleIdentifier: snapshot.bundleIdentifier, role: snapshot.role),
            typed: typed, generation: 1)
    }

    @Test func terminalsKeepRecentLinesWithoutWalkingTheWindow() async throws {
        let corpus = try SituationCorpus()
        let snapshot = Self.snapshot(bundle: "com.apple.Terminal")
        let query = Self.query(snapshot)
        try await corpus.store.record("an earlier line", in: query.surface, at: Date())
        let window = SituationWindow()
        let built = await SuggestionSituationBuilder.situation(
            of: snapshot, for: query, store: corpus.store, cache: SuggestionContextCache(), turn: 1,
            readingWindow: { await window.read(Self.around) }, log: Self.log)
        #expect(await window.reads == 0)
        #expect(
            built
                == SuggestionMoment.situation(
                    of: snapshot, surroundings: nil, recentLines: ["an earlier line"]))
        let defaultReader = await SuggestionSituationBuilder.situation(
            of: snapshot, for: query, store: corpus.store, cache: SuggestionContextCache(), turn: 2,
            readingWindow: FocusedFieldReader.surroundings, log: Self.log)
        #expect(defaultReader == built)
    }

    @Test func theRealCorpusLimitAndTypingFilterKeepTheirOriginalOrder() async throws {
        let corpus = try SituationCorpus()
        let snapshot = Self.snapshot()
        let query = Self.query(snapshot, typed: "line seven continued")
        let moment = Date(timeIntervalSince1970: 1_000)
        let lines = [
            "line one", "line two", "line three", "line four", "line five", "line six", "line seven",
        ]
        for (index, line) in lines.enumerated() {
            try await corpus.store.record(
                line, in: query.surface, at: moment.addingTimeInterval(Double(index)))
        }
        let window = SituationWindow()
        let built = await SuggestionSituationBuilder.situation(
            of: snapshot, for: query, store: corpus.store, cache: SuggestionContextCache(), turn: 1,
            readingWindow: { await window.read(Self.around) }, log: Self.log)
        #expect(await window.reads == 1)
        #expect(built.recentLines == ["line six", "line five", "line four", "line three", "line two"])
        #expect(
            built
                == SuggestionMoment.situation(
                    of: snapshot, surroundings: Self.around, recentLines: built.recentLines))
    }

    @Test func aTurnHitSkipsBothReadersAndTheNextTurnReusesOnlyTheWindow() async throws {
        let corpus = try SituationCorpus()
        let snapshot = Self.snapshot()
        let query = Self.query(snapshot)
        let window = SituationWindow()
        let cache = SuggestionContextCache()
        let instant = ContinuousClock.now
        var logs = 0
        let first = await SuggestionSituationBuilder.situation(
            of: snapshot, for: query, store: corpus.store, cache: cache, turn: 1,
            readingWindow: { await window.read(Self.around) }, windowTime: { instant },
            log: { around, recent, situation in
                logs += 1
                #expect(around == Self.around)
                #expect(recent.isEmpty)
                #expect(
                    situation
                        == SuggestionMoment.situation(of: snapshot, surroundings: around, recentLines: recent)
                )
            })
        #expect(logs == 1)
        try await corpus.store.record("new remembered line", in: query.surface, at: Date())
        let repeated = await SuggestionSituationBuilder.situation(
            of: snapshot, for: query, store: corpus.store, cache: cache, turn: 1,
            readingWindow: { await window.read(nil) }, windowTime: { instant }, log: { _, _, _ in logs += 1 })
        #expect(logs == 1)
        #expect(repeated == first)
        #expect(await window.reads == 1)
        let next = await SuggestionSituationBuilder.situation(
            of: snapshot, for: query, store: corpus.store, cache: cache, turn: 2,
            readingWindow: { await window.read(nil) }, windowTime: { instant }, log: Self.log)
        #expect(await window.reads == 1)
        #expect(next.surroundings == Self.around.text)
        #expect(next.recentLines == ["new remembered line"])
        let changedWindow = Self.snapshot(window: 8)
        _ = await SuggestionSituationBuilder.situation(
            of: changedWindow, for: query, store: corpus.store, cache: cache, turn: 3,
            readingWindow: { await window.read(nil) }, windowTime: { instant }, log: Self.log)
        #expect(await window.reads == 2)
    }

    @Test func windowNilAndARealStoreQueryFailureStillBuildTheFieldContext() async throws {
        let corpus = try SituationCorpus()
        try await breakSituationCorpus(corpus.store)
        let snapshot = Self.snapshot()
        let cache = SuggestionContextCache()
        let window = SituationWindow()
        let built = await SuggestionSituationBuilder.situation(
            of: snapshot, for: Self.query(snapshot), store: corpus.store, cache: cache, turn: 4,
            readingWindow: { await window.read(nil) }, log: Self.log)
        #expect(await window.reads == 1)
        #expect(built == SuggestionMoment.situation(of: snapshot, surroundings: nil, recentLines: []))
        #expect(await cache.situation(forTurn: 4) == built)
    }

    @Test func cancellingTheAsyncLetWalkKeepsItsTaskLocalAndCancelsTheSharedFlight() async throws {
        let corpus = try SituationCorpus()
        let snapshot = Self.snapshot()
        let query = Self.query(snapshot)
        let window = SituationWindow()
        let cache = SuggestionContextCache()
        let task = SituationTaskMarker.$value.withValue(71) {
            Task {
                await SuggestionSituationBuilder.situation(
                    of: snapshot, for: query, store: corpus.store, cache: cache, turn: 5,
                    readingWindow: { await window.heldRead() },
                    log: { _, _, _ in
                        #expect(SituationTaskMarker.value == 71)
                        #expect(Task.isCancelled)
                    })
            }
        }
        try await eventually { await window.reads == 1 }
        task.cancel()
        let answer = await task.value
        try await eventually { await window.wasCancelled }
        #expect(await window.markers == [71, 71])
        #expect(answer == SuggestionMoment.situation(of: snapshot, surroundings: nil, recentLines: []))
        #expect(await cache.situation(forTurn: 5) == answer)
    }
}
