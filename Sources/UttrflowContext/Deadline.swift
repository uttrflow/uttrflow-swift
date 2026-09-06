private import Synchronization

/// Holds an answer to a time, so a read into another application can never hold the loop.
enum Deadline {
    /// The work's answer if it arrives within the allowance, else nothing, the work cancelled and left to finish on its own.
    static func first<Answer: Sendable>(
        within allowance: Duration,
        on clock: any Clock<Duration> = ContinuousClock(),
        of work: @escaping @Sendable () async -> Answer?
    ) async -> Answer? {
        var timer: Task<Void, Never>?
        // Two free-standing tasks rather than a group, since a group waits for the loser and a stalled read would hold the caller.
        let answer: Answer? = await withCheckedContinuation { continuation in
            let finish = Finish<Answer>(continuation)
            let worker = Task { finish.settle(await work()) }
            timer = Task {
                try? await clock.sleep(for: max(allowance, .milliseconds(1)))
                if finish.settle(nil) { worker.cancel() }
            }
        }
        // Cancelled so a clock that sleeps for real does not leave a task per read.
        timer?.cancel()
        return answer
    }

    /// The caller's continuation, resumed by whichever side settles first and by nobody after.
    private final class Finish<Answer: Sendable>: Sendable {
        private let waiting: Mutex<CheckedContinuation<Answer?, Never>?>

        init(_ continuation: CheckedContinuation<Answer?, Never>) {
            waiting = Mutex(continuation)
        }

        /// Hands the answer to the caller, and says whether this was the side that got there first.
        @discardableResult
        func settle(_ answer: Answer?) -> Bool {
            guard
                let continuation = waiting.withLock({ waiting in
                    defer { waiting = nil }
                    return waiting
                })
            else { return false }
            continuation.resume(returning: answer)
            return true
        }
    }
}
