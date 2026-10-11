// Checks model release ownership without loading weights or touching the GPU.
import os
import Testing
import UttrflowTestSupport
@testable import UttrflowLocalModel

@Suite("Scorer release ownership", .timeLimit(.minutes(1)))
struct ScorerLifecycleTests {
    @Test("release forgets retained answers before waiting for every active pass")
    func releaseWaitsForEveryPass() async throws {
        let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
        let control = BufferCacheControl(
            hold: { calls.withLock { $0.append("hold") } },
            clear: { calls.withLock { $0.append("clear") } })
        var memory = ConfidenceMemory()
        memory.remember(["example answer": -0.25])
        let scorer = MLXCandidateScorer(
            model: .gemma3, maximumTokens: 16, bufferCache: control,
            initialConfidenceMemory: memory)
        await scorer.beginPass()
        await scorer.beginPass()
        let releasing = Task { await scorer.release() }
        try await eventually { await scorer.confidence(ofGenerated: "example answer") == nil }
        #expect(calls.withLock { $0 } == ["hold"])
        await scorer.endPass()
        #expect(calls.withLock { $0 } == ["hold"])
        await scorer.endPass()
        await releasing.value
        #expect(calls.withLock { $0 } == ["hold", "clear", "hold", "clear"])
        #expect(!(await scorer.isReady))
    }
}
