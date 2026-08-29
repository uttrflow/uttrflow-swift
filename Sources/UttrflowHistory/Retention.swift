public import struct Foundation.Date

/// How long dictations are kept, and the instant to reckon that from.
///
/// The two travel together because neither decides anything alone: "seven days" is not
/// a rule until there is a *now* to measure back from. Passed in rather than held,
/// because both belong to the caller — the window lives in the user's settings, which
/// this module deliberately does not depend on, and a store that read the clock itself
/// is a store no test can pin down.
public struct Retention: Sendable, Equatable {
    /// How many days a dictation is kept for. Zero or fewer keeps nothing, which is
    /// what ``DictationRecord/survives(days:now:)`` already decides.
    public let days: Int

    /// The moment the window is measured back from.
    public let now: Date

    public init(days: Int, now: Date) {
        self.days = days
        self.now = now
    }
}
