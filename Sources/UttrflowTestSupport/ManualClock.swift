private import Synchronization

/// A `Clock` that only moves when a test tells it to.
///
/// Latency assertions have to be exact and instant; measuring against a real clock
/// would make them both slow and flaky.
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

    private let current = Mutex(Instant(offset: .zero))

    public init() {}

    public var now: Instant { current.withLock { $0 } }

    public var minimumResolution: Duration { .nanoseconds(1) }

    /// Moves the clock forward. Nothing in the product sleeps on this clock, so this
    /// is the only way time passes.
    public func advance(by duration: Duration) {
        current.withLock { $0 = $0.advanced(by: duration) }
    }

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        current.withLock { instant in
            if instant < deadline { instant = deadline }
        }
    }
}
