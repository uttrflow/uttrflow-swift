import Synchronization
import Testing
import UttrflowCore
import UttrflowTestSupport

@testable import UttrflowAI
@testable import UttrflowEval

/// An engine that takes `delay` on the test's clock, then answers as the rules do.
private final class SlowEngine: TextTransformationEngine, Sendable {
    let kind = TransformerKind.foundationModels
    let clock: ManualClock
    let delay: Duration
    private let began = Mutex(false)

    var hasBegun: Bool { began.withLock { $0 } }

    init(clock: ManualClock, delay: Duration) {
        self.clock = clock
        self.delay = delay
    }

    func availability(for request: TransformationRequest) async -> TransformerAvailability { .available }

    func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        let end = clock.now.advanced(by: delay)
        began.withLock { $0 = true }
        do { try await clock.sleep(until: end, tolerance: nil) } catch { throw .cancelled }
        let answer = try await RuleBasedTransformer().transform(request)
        return TransformationResult(text: answer.text, producedBy: kind)
    }
}

@Suite("The same words come out however loaded the Mac is, until a backstop fires")
struct LoadInvarianceTests {
    /// What the router writes for `request` when its model engine takes `delay` before it answers.
    private static func written(
        _ request: TransformationRequest, after delay: Duration
    ) async throws -> String {
        let clock = ManualClock()
        let engine = SlowEngine(clock: clock, delay: delay)
        let router = TransformerRouter(
            engines: [engine, RuleBasedTransformer()], preference: [.foundationModels, .rules], clock: clock)
        async let result = router.transform(request)
        while !engine.hasBegun { await Task.yield() }
        clock.advance(by: delay)
        return try await result.text
    }

    @Test("an engine at 80% of its backstop writes the same text as an instant one", arguments: sample)
    func slowedEngineWritesTheSameText(testCase: EvaluationCase) async throws {
        let request = testCase.transformationRequest()
        let instant = try await Self.written(request, after: .zero)
        let slowed = try await Self.written(request, after: StageTimeout.engine * 0.8)
        #expect(slowed == instant, "\(testCase.id)")
    }

    /// Every fifth evaluation case, so the run covers the corpus's classes without repeating every case twice.
    static let sample: [EvaluationCase] = EvaluationCorpus.all.enumerated()
        .filter { $0.offset % 5 == 0 }.map(\.element)
}
