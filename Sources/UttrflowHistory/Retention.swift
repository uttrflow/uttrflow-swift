public import struct Foundation.Date

/// How long dictations are kept and the instant to reckon from; passed in so the store never reads a clock.
public struct Retention: Sendable, Equatable {
    /// Days a dictation is kept; zero or fewer keeps nothing, per ``DictationRecord/survives(days:now:)``.
    public let days: Int

    /// The moment the window is measured back from.
    public let now: Date

    /// Pairs a window with the moment it is measured from.
    public init(days: Int, now: Date) {
        self.days = days
        self.now = now
    }
}
