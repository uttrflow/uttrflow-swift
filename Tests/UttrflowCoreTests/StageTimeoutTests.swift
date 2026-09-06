// Tests for withStageTimeout.

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
}
