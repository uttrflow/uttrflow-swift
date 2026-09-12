// Tests for withStageTimeout.

import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowTestSupport

@Suite("withStageTimeout")
struct StageTimeoutTests {
    @Test("returns the work's answer when it finishes first", .timeLimit(.minutes(1)))
    func workWinsAgainstAClockThatNeverMoves() async throws {
        let clock = ManualClock()
        let answer = try await withStageTimeout(.seconds(15), clock: clock) { "done" }
        #expect(answer == "done")
    }

    @Test("answers nothing once the limit has passed", .timeLimit(.minutes(1)))
    func timeoutWins() async throws {
        let clock = ManualClock()
        let running = Task {
            try await withStageTimeout(.seconds(15), clock: clock) {
                await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
                return "never"
            }
        }
        await clock.advanceWhenSomethingIsWaiting(by: .seconds(15))
        #expect(try await running.value == nil)
    }

    @Test("carries the work's own error out", .timeLimit(.minutes(1)))
    func workErrorsPropagate() async {
        let clock = ManualClock()
        await #expect(throws: SpeechEngineError.self) {
            try await withStageTimeout(.seconds(15), clock: clock) {
                throw SpeechEngineError.nothingHeard
            }
        }
    }

    /// A stage that is over has to mean one thing, or the work goes on having effects nobody waits for.
    @Test("cancels the work when the limit wins", .timeLimit(.minutes(1)))
    func cancelsTheWorkItStoppedWaitingFor() async throws {
        let clock = ManualClock()
        let cancelled = Mutex(false)
        let running = Task {
            try await withStageTimeout(.seconds(15), clock: clock) {
                await withTaskCancellationHandler {
                    await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
                } onCancel: {
                    cancelled.withLock { $0 = true }
                }
                return "never"
            }
        }
        await clock.advanceWhenSomethingIsWaiting(by: .seconds(15))
        _ = try await running.value

        // Polled rather than assumed: cancellation reaches the handler on its own task.
        while !cancelled.withLock({ $0 }) { await Task.yield() }
        #expect(cancelled.withLock { $0 })
    }

    @Test("leaves work that answered in time alone", .timeLimit(.minutes(1)))
    func doesNotCancelWorkThatFinished() async throws {
        let clock = ManualClock()
        let answer = try await withStageTimeout(.seconds(15), clock: clock) {
            Task.isCancelled ? "cancelled" : "done"
        }
        #expect(answer == "done")
    }
}
