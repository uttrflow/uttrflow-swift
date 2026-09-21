// A serial queue that runs only the newest request, since a read nobody waits for still costs the next one.

internal import Dispatch
private import Synchronization

/// Runs blocking reads one at a time, skipping any that a newer request has replaced. See `Docs/predict.md`.
final class LatestOnlyQueue: Sendable {
    private let queue: DispatchQueue
    /// The newest request's number, which every queued block compares itself with.
    private let latest: Latest = Latest()

    init(label: String, qos: DispatchQoS) {
        queue = DispatchQueue(label: label, qos: qos)
    }

    /// How many requests have taken a number, which is how a test queues one behind another without a sleep.
    var requested: Int { latest.count }

    /// Runs `work` on the queue under `allowance`, unless a newer request arrives before it starts.
    func run<Answer: Sendable>(
        within allowance: Duration,
        _ work: @escaping @Sendable (_ isWanted: @Sendable () -> Bool) -> Answer?
    ) async -> Answer? {
        let latest = self.latest
        let ticket = latest.next()
        let isWanted: @Sendable () -> Bool = { latest.isCurrent(ticket) }
        return await Deadline.first(within: allowance) { [queue] in
            await withCheckedContinuation { continuation in
                queue.async { [isWanted] in
                    // A read whose turn has been replaced is dropped here, before it sends a single message.
                    guard isWanted() else { return continuation.resume(returning: nil) }
                    continuation.resume(returning: work(isWanted))
                }
            }
        }
    }
}

/// The newest request's number, shared by every block the queue holds.
private final class Latest: Sendable {
    private let number = Mutex(0)

    /// Takes the next number, which makes every earlier request unwanted.
    func next() -> Int {
        number.withLock { current in
            current += 1
            return current
        }
    }

    /// Whether this request is still the newest one.
    func isCurrent(_ ticket: Int) -> Bool { number.withLock { $0 } == ticket }

    /// How many numbers have been taken.
    var count: Int { number.withLock { $0 } }
}
