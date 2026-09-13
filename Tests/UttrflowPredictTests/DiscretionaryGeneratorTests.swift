// Tests that a suggestion pass runs as discretionary work and starts none while the Mac asks for less.

import Synchronization
import Testing

@testable import UttrflowPredict

/// A generator that records the priority each pass ran at, and can hold a pass until it is cancelled.
private final class RecordingGenerator: CandidateGenerating, Sendable {
    private let priorities = Mutex<[TaskPriority]>([])
    private let holds: Bool

    init(holds: Bool = false) {
        self.holds = holds
    }

    var seen: [TaskPriority] { priorities.withLock { $0 } }

    var isReady: Bool { true }

    func completions(for typed: String, in situation: GenerationSituation) async throws -> [String] {
        priorities.withLock { $0.append(Task.currentPriority) }
        if holds { try await Task.sleep(for: .seconds(600)) }
        return [typed + " completed"]
    }

    func alternatives(
        for typed: String, in situation: GenerationSituation, excluding leader: String
    ) async throws -> [String] {
        priorities.withLock { $0.append(Task.currentPriority) }
        return [typed + " otherwise"]
    }
}

@Suite("A suggestion pass as discretionary work")
struct DiscretionaryGeneratorTests {
    private let situation = GenerationSituation(application: "Notes")

    @Test("runs each pass at utility priority, even when asked from the main thread's priority")
    func runsAtUtility() async throws {
        let inner = RecordingGenerator()
        let generator = DiscretionaryGenerator(inner, mayRun: { true })

        let lines = try await Task(priority: .userInitiated) {
            try await generator.completions(for: "see you", in: situation)
                + generator.alternatives(for: "see you", in: situation, excluding: "see you completed")
        }.value

        #expect(lines == ["see you completed", "see you otherwise"])
        #expect(inner.seen.count == 2)
        #expect(inner.seen.allSatisfy { $0 <= .utility })
    }

    @Test("is ready when the Mac allows it and the model is")
    func readyWhenAllowed() async {
        #expect(await DiscretionaryGenerator(RecordingGenerator(), mayRun: { true }).isReady)
    }

    @Test("is not ready while the Mac asks for less, so no pass is started")
    func notReadyWhenRefused() async {
        #expect(!(await DiscretionaryGenerator(RecordingGenerator(), mayRun: { false }).isReady))
    }

    @Test("starts no pass when the Mac began asking for less after readiness was checked")
    func refusesAPassLate() async throws {
        let inner = RecordingGenerator()
        let generator = DiscretionaryGenerator(inner, mayRun: { false })

        #expect(try await generator.completions(for: "see you", in: situation).isEmpty)
        #expect(try await generator.alternatives(for: "see you", in: situation, excluding: "x").isEmpty)
        #expect(inner.seen.isEmpty)
    }

    @Test("still stops the pass when the caller is cancelled", .timeLimit(.minutes(1)))
    func cancellationReachesThePass() async {
        let inner = RecordingGenerator(holds: true)
        let generator = DiscretionaryGenerator(inner, mayRun: { true })
        let situation = situation

        let pass = Task { try await generator.completions(for: "see you", in: situation) }
        while inner.seen.isEmpty { await Task.yield() }
        pass.cancel()

        await #expect(throws: CancellationError.self) { try await pass.value }
    }
}
