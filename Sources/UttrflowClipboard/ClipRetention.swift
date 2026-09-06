// How long unkept clips are kept.

public import struct Foundation.Date

/// How long unkept clips are kept and the instant to reckon from; both passed in, neither read here.
public struct ClipRetention: Sendable, Equatable {
    /// How many days an unkept clip survives; zero or fewer keeps no history.
    public let days: Int

    /// How long a dictation survives here when that differs from `days`; `nil` uses `days`.
    public let dictationDays: Int?

    /// The moment the window is measured back from.
    public let now: Date

    public init(days: Int, now: Date, dictationDays: Int? = nil) {
        self.days = days
        self.now = now
        self.dictationDays = dictationDays
    }
}
