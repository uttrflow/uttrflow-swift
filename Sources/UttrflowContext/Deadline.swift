private import Synchronization

/// Holds an answer to a time, so a read into another application can never hold the loop.
public enum Deadline {
    /// The work's answer if it arrives within the allowance, else nothing, the work cancelled and left to finish on its own.
    public static func first<Answer: Sendable>(
        withinMilliseconds allowance: Int, of work: @escaping @Sendable () async -> Answer?
    ) async -> Answer? {
        // Two free-standing tasks rather than a group, since a group waits for the loser and a stalled read would hold the caller.
        await withCheckedContinuation { continuation in
            let finish = Finish(continuation)
            let worker = Task { finish.settle(await work()) }
            Task {
                try? await Task.sleep(for: .milliseconds(max(allowance, 1)))
                if finish.settle(nil) { worker.cancel() }
            }
        }
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
