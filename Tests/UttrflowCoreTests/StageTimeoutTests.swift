// Tests for withStageTimeout.

import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowTestSupport

@Suite("withStageTimeout", .timeLimit(.minutes(1)))
struct StageTimeoutTests {
    private func suspendUntilCancelled(_ cancelled: borrowing Mutex<Bool>) async {
        let continuation = Mutex<CheckedContinuation<Void, Never>?>(nil)
        await withTaskCancellationHandler {
            await withCheckedContinuation { (parked: CheckedContinuation<Void, Never>) in
                let resumeNow = continuation.withLock { state -> Bool in
                    if cancelled.withLock({ $0 }) { return true }
                    state = parked
                    return false
                }
                if resumeNow { parked.resume() }
            }
        } onCancel: {
            cancelled.withLock { $0 = true }
            let parked = continuation.withLock { state -> CheckedContinuation<Void, Never>? in
                defer { state = nil }
                return state
            }
            parked?.resume()
        }
    }

    @Test("the transcription limit grows with the audio from its floor")
    func transcriptionLimitFollowsAudioLength() {
        #expect(StageTimeout.transcription(of: .zero) == StageTimeout.transcription)
        #expect(StageTimeout.transcription(of: .seconds(240)) == .seconds(360))
        #expect(StageTimeout.transcription(of: .seconds(-5)) == StageTimeout.transcription)
    }

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
                await suspendUntilCancelled(Mutex(false))
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
                await suspendUntilCancelled(cancelled)
                return "never"
            }
        }
        await clock.advanceWhenSomethingIsWaiting(by: .seconds(15))
        _ = try await running.value

        // Polled rather than assumed: cancellation reaches the handler on its own task.
        try await eventually { cancelled.withLock { $0 } }
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

    @Test("returns promptly when the caller was already cancelled", .timeLimit(.minutes(1)))
    func cancellationBeforeWork() async throws {
        let clock = ManualClock()
        let gate = Mutex<CheckedContinuation<Void, Never>?>(nil)
        let running = Task {
            await withCheckedContinuation { continuation in gate.withLock { $0 = continuation } }
            return try await withStageTimeout(.seconds(15), clock: clock) {
                await suspendUntilCancelled(Mutex(false))
                return "never"
            }
        }
        while gate.withLock({ $0 == nil }) { await Task.yield() }
        running.cancel()
        gate.withLock { continuation in
            continuation?.resume()
            continuation = nil
        }

        #expect(try await running.value == nil)
    }

    @Test("cancels suspended work and resumes the caller", .timeLimit(.minutes(1)))
    func cancellationWhileWorkIsSuspended() async throws {
        let clock = ManualClock()
        let started = Mutex(false)
        let cancelled = Mutex(false)
        let running = Task {
            try await withStageTimeout(.seconds(15), clock: clock) {
                started.withLock { $0 = true }
                await suspendUntilCancelled(cancelled)
                return "never"
            }
        }
        try await eventually { started.withLock { $0 } }
        running.cancel()

        #expect(try await running.value == nil)
        #expect(cancelled.withLock { $0 })
    }

    @Test("resolves timeout and cancellation races once", .timeLimit(.minutes(1)))
    func timeoutRacesCancellation() async throws {
        let clock = ManualClock()
        let running = Task {
            try await withStageTimeout(.seconds(15), clock: clock) {
                await suspendUntilCancelled(Mutex(false))
                return "never"
            }
        }
        await clock.waitUntilSomethingIsWaiting()
        running.cancel()
        clock.advance(by: .seconds(15))

        #expect(try await running.value == nil)
    }

    @Test("resolves work completion and cancellation races once", .timeLimit(.minutes(1)))
    func workCompletionWinsAgainstCancellation() async throws {
        let clock = ManualClock()
        let resumed = Mutex(false)
        let release = Mutex<CheckedContinuation<Void, Never>?>(nil)
        let running = Task {
            try await withStageTimeout(.seconds(15), clock: clock) {
                await withTaskCancellationHandler {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        let resumeNow = release.withLock { parked -> Bool in
                            if resumed.withLock({ $0 }) { return true }
                            parked = continuation
                            return false
                        }
                        if resumeNow { continuation.resume() }
                    }
                } onCancel: {
                    resumed.withLock { $0 = true }
                    release.withLock { continuation in
                        continuation?.resume()
                        continuation = nil
                    }
                }
                return "done"
            }
        }
        await clock.waitUntilSomethingIsWaiting()
        try await eventually { release.withLock { $0 != nil } }
        resumed.withLock { $0 = true }
        let released = release.withLock { continuation -> Bool in
            guard let parked = continuation else { return false }
            parked.resume()
            continuation = nil
            return true
        }
        #expect(released)
        running.cancel()
        let answer = try await running.value
        #expect(answer == "done" || answer == nil)
    }
}
