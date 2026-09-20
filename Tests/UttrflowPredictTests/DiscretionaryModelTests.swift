// Tests that the suggestion model's scores, loads and releases run as discretionary work.

import Synchronization
import Testing

@testable import UttrflowPredict

/// A model that records the priority each call ran at, by name.
private final class RecordingModel: ReleasableModel, Sendable {
    private let calls = Mutex<[(String, TaskPriority)]>([])

    var seen: [(String, TaskPriority)] { calls.withLock { $0 } }

    private func note(_ name: String) { calls.withLock { $0.append((name, Task.currentPriority)) } }

    var isReady: Bool { true }

    func logLikelihood(of candidate: String, following context: String) async -> Double? {
        note("score")
        return -1.5
    }

    func completions(for typed: String, in situation: GenerationSituation) async throws -> [String] { [] }

    func alternatives(
        for typed: String, in situation: GenerationSituation, excluding leader: String
    ) async throws -> [String] { [] }

    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        note("prepare")
        onProgress(1)
    }

    func reload() async throws { note("reload") }

    func release() async { note("release") }
}

@Suite("The suggestion model's scores, loads and releases as discretionary work")
struct DiscretionaryModelTests {
    @Test("a bare model runs at the priority of whoever asks, which is why it is wrapped")
    func bareModelInheritsPriority() async {
        let inner = RecordingModel()
        _ = await Task(priority: .userInitiated) {
            await inner.logLikelihood(of: "see you soon", following: "see you")
        }.value
        #expect(inner.seen.map(\.1) == [.userInitiated])
    }

    @Test("scores, loads and releases at utility priority, even when asked from the main thread's priority")
    func runsAtUtility() async throws {
        let inner = RecordingModel()
        let model = DiscretionaryModel(inner, mayRun: { true })

        let score = try await Task(priority: .userInitiated) {
            try await model.prepare(onProgress: { _ in })
            let score = await model.logLikelihood(of: "see you soon", following: "see you")
            await model.release()
            return score
        }.value

        #expect(score == -1.5)
        #expect(inner.seen.map(\.0) == ["prepare", "score", "release"])
        #expect(inner.seen.allSatisfy { $0.1 <= .utility })
    }

    @Test("is ready when the Mac allows it and the model is")
    func readyWhenAllowed() async {
        #expect(await DiscretionaryModel(RecordingModel(), mayRun: { true }).isReady)
    }

    @Test("scores nothing while the Mac asks for less, but still loads and releases")
    func refusesScoresWhenRefused() async throws {
        let inner = RecordingModel()
        let model = DiscretionaryModel(inner, mayRun: { false })

        #expect(!(await model.isReady))
        #expect(await model.logLikelihood(of: "see you soon", following: "see you") == nil)
        try await model.prepare(onProgress: { _ in })
        await model.release()
        #expect(inner.seen.map(\.0) == ["prepare", "release"])
    }

    @Test("scores nothing while a dictation is under way, and scores again once it ends")
    func refusesScoresWhileDictating() async {
        let inner = RecordingModel()
        let activity = DictationInProgress()
        let model = DiscretionaryModel(inner, mayRun: { !activity.isDictating })

        activity.set(dictating: true)
        #expect(await model.logLikelihood(of: "see you soon", following: "see you") == nil)
        #expect(inner.seen.isEmpty)

        activity.set(dictating: false)
        #expect(await model.logLikelihood(of: "see you soon", following: "see you") != nil)
        #expect(inner.seen.map(\.0) == ["score"])
    }
}
