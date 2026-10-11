// The time a tidier spends starting a session that nothing warmed, handed to the pipeline without changing the tidier's answer.
import Synchronization

/// Adds up the time a cleanup model spent on a request that found no warm session, while bound to ``current``.
public final class ColdStartMeter: Sendable {
    /// The meter the tidying under way reports to, or `nil` where nobody is listening.
    @TaskLocal public static var current: ColdStartMeter?

    private let spent = Mutex(Duration.zero)

    /// A meter that has seen no cold start.
    public init() {}

    /// Everything reported so far.
    public var total: Duration { spent.withLock { $0 } }

    /// Adds `duration` to the total.
    public func add(_ duration: Duration) { spent.withLock { $0 += duration } }
}
