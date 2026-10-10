// Tests that a release asked for during a load stops that load instead of waiting for it to finish.

import Foundation
import Testing
import UttrflowTestSupport

@testable import UttrflowPredict

/// A model whose next load runs until it is stopped, as a download or a slow read does.
private actor SlowLoad: ReleasableModel {
    private(set) var isLoaded = false
    private(set) var finishedLoads = 0
    private(set) var stoppedLoads = 0
    private var slowNext: Bool
    /// Fires when the slow load has begun.
    let slowLoadStarted = Signal()

    init(slowFirst: Bool = true) {
        slowNext = slowFirst
    }

    /// Makes the next load run until it is stopped.
    func slowNextLoad() { slowNext = true }

    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        if slowNext {
            slowNext = false
            slowLoadStarted.fire()
            do {
                try await Task.sleep(for: .seconds(3_600))
            } catch {
                stoppedLoads += 1
                throw error
            }
        }
        finishedLoads += 1
        isLoaded = true
    }

    func reload() async throws { try await prepare(onProgress: { _ in }) }

    func release() async { isLoaded = false }

    func forgetPrefixIndex() {}

    var isReady: Bool { isLoaded }

    func completions(for typed: String, in situation: GenerationSituation) async throws -> [String] { [] }

    func alternatives(
        for typed: String, in situation: GenerationSituation, excluding leader: String
    ) async throws -> [String] { [] }

    func logLikelihood(of candidate: String, following context: String) async -> Double? { nil }

    func confidence(ofGenerated line: String) async -> Double? { nil }
}

@Suite("A release stops the load in flight", .timeLimit(.minutes(1)))
struct IdleReleaseCancellationTests {
    @Test("a release during a slow prepare returns without the load finishing, and a later prepare loads")
    func releaseStopsAPrepare() async throws {
        let inner = SlowLoad()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(3_600))
        let first = Task { try await model.prepare(onProgress: { _ in }) }
        try await arrival(of: inner.slowLoadStarted.fired)
        await model.release()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await inner.stoppedLoads == 1)
        #expect(await inner.finishedLoads == 0)
        #expect(await !inner.isLoaded)
        try await model.prepare(onProgress: { _ in })
        #expect(await inner.isLoaded)
        #expect(await model.holdsTheModel)
    }

    @Test("a caller that stops its prepare stops the load")
    func aStoppedCallerStopsThePrepare() async throws {
        let inner = SlowLoad()
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(3_600))
        let first = Task { try await model.prepare(onProgress: { _ in }) }
        try await arrival(of: inner.slowLoadStarted.fired)
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await inner.finishedLoads == 0)
    }

    @Test("a release during a query's reload stops the reload")
    func releaseStopsAReload() async throws {
        let inner = SlowLoad(slowFirst: false)
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(3_600))
        try await model.prepare(onProgress: { _ in })
        await model.releaseIfIdle(at: .seconds(7_200))
        await inner.slowNextLoad()
        #expect(await !model.isReady)
        try await arrival(of: inner.slowLoadStarted.fired)
        await model.release()
        await model.pendingWork?.value
        #expect(await inner.stoppedLoads == 1)
        #expect(await !inner.isLoaded)
    }
}
