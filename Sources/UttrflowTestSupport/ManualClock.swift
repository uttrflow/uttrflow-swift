private import Synchronization

/// A `Clock` that only moves when a test tells it to, so sleeping on it costs nothing.
public final class ManualClock: Clock, Sendable {
    public struct Instant: InstantProtocol, Sendable {
        public let offset: Duration

        public init(offset: Duration) {
            self.offset = offset
        }

        public func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        public static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    /// One caller waiting for the clock to reach a deadline.
    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// An advance waiting for something to sleep, so the two can happen under one lock.
    private struct ParkedAdvance {
        let duration: Duration
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [Sleeper] = []
        /// Sleepers cancelled before they were installed, which a task group does routinely.
        var cancelledBeforeSleeping: Set<Int> = []
        var nextID = 0
        var parkedAdvance: ParkedAdvance?
    }

    /// Moves the clock and collects what that woke, with the lock already held.
    private static func advance(_ state: inout State, by duration: Duration) -> [Sleeper] {
        state.now = state.now.advanced(by: duration)
        let reached = state.sleepers.filter { $0.deadline <= state.now }
        state.sleepers.removeAll { $0.deadline <= state.now }
        return reached
    }

    private let state = Mutex(State())

    public init() {}

    public var now: Instant { state.withLock(\.now) }

    public var minimumResolution: Duration { .nanoseconds(1) }

    /// Moves the clock forward, waking everything sleeping up to the new time.
    public func advance(by duration: Duration) {
        let due = state.withLock { Self.advance(&$0, by: duration) }
        for sleeper in due { sleeper.continuation.resume() }
    }

    /// Advances by `duration` under the lock that finds something waiting. See `Docs/stuck-recording.md`.
    public func advanceWhenSomethingIsWaiting(by duration: Duration) async {
        await withCheckedContinuation { continuation in
            let due = state.withLock { state -> [Sleeper]? in
                guard !state.sleepers.isEmpty else {
                    state.parkedAdvance = ParkedAdvance(
                        duration: duration, continuation: continuation)
                    return nil
                }
                return Self.advance(&state, by: duration)
            }
            guard let due else { return }
            for sleeper in due { sleeper.continuation.resume() }
            continuation.resume()
        }
    }

    /// Suspends until something is waiting on this clock.
    public func waitUntilSomethingIsWaiting() async {
        await advanceWhenSomethingIsWaiting(by: .zero)
    }

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = state.withLock { state -> Int in
            state.nextID += 1
            return state.nextID
        }
        enum Outcome { case wait, reached, cancelled }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var woken: [Sleeper] = []
                var waiting: CheckedContinuation<Void, Never>?
                let outcome = state.withLock { state -> Outcome in
                    if state.cancelledBeforeSleeping.remove(id) != nil { return .cancelled }
                    guard state.now < deadline else { return .reached }
                    state.sleepers.append(
                        Sleeper(id: id, deadline: deadline, continuation: continuation))
                    // Still holding the lock, so nothing can be removed in between.
                    if let parked = state.parkedAdvance {
                        state.parkedAdvance = nil
                        woken = Self.advance(&state, by: parked.duration)
                        waiting = parked.continuation
                    }
                    return .wait
                }
                switch outcome {
                case .wait:
                    for sleeper in woken { sleeper.continuation.resume() }
                    waiting?.resume()
                case .reached: continuation.resume()
                case .cancelled: continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let cancelled = state.withLock { state -> Sleeper? in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else {
                    // Not installed yet, so leave a note for the body to find.
                    state.cancelledBeforeSleeping.insert(id)
                    return nil
                }
                return state.sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }
}
