public import struct Foundation.Date

/// How long unkept clips are kept for, and the instant to reckon that from.
///
/// The two travel together because neither decides anything alone: "seven days" is not
/// a rule until there is a *now* to measure back from. Passed in rather than held,
/// because both belong to the caller — the window lives in the user's settings, which
/// this module deliberately does not depend on, and a store that read the clock itself
/// is a store no test can pin down.
///
/// It says nothing about kept clips, and that is the point. There is no second number
/// here for aliased, filed or pinned clips because there is no clock on them at all.
public struct ClipRetention: Sendable, Equatable {
    /// How many days an unkept clip survives. Zero or fewer keeps no history, which is
    /// a legitimate setting for someone who wants the panel and not the record.
    public let days: Int

    /// How long a dictation survives here, when that differs from `days`.
    ///
    /// A dictation is written to two files: the history, and this one. They had two
    /// windows, and only the history's was on a screen — so somebody who set their
    /// transcripts to be kept for one day still had every one of them in the clipboard
    /// a fortnight later, reachable from the panel, with nothing anywhere saying so.
    ///
    /// The Privacy pane's one control governs both now. `nil` keeps the old behaviour for
    /// any caller that has no opinion, which is every test that predates this.
    public let dictationDays: Int?

    /// The moment the window is measured back from.
    public let now: Date

    public init(days: Int, now: Date, dictationDays: Int? = nil) {
        self.days = days
        self.now = now
        self.dictationDays = dictationDays
    }
}
