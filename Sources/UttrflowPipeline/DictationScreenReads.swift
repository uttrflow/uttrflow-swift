import UttrflowCore

/// The screen reads of the dictation under way, kept so a reading no input has outdated is not taken twice.
struct DictationScreenReads {
    /// How many reads the dictation took and how long they took together, reported once when it settles.
    private(set) var cost = ScreenReadCost(reads: 0, duration: .zero)
    /// The latest complete reading, with the engine's input count from just before it began.
    private var latest: (context: AppContext, inputsBefore: Int)?
    /// Why the newest read carried no field text, or `nil` when it did.
    private(set) var lastUnavailable: ContextUnavailableReason?

    /// Counts one read of `elapsed`; it can stand in for the next only when complete and the engine counted input before it.
    mutating func record(_ read: AppContext, took elapsed: Duration, inputsBefore: Int?) {
        cost = cost.adding(elapsed)
        lastUnavailable = read.unavailable
        latest = inputsBefore.flatMap { read.unavailable == nil ? (read, $0) : nil }
    }

    /// The latest reading, when no key, click or application switch has come since it began.
    func unchanged(inputsNow: Int?) -> AppContext? {
        guard let latest, let inputsNow, inputsNow == latest.inputsBefore else { return nil }
        return latest.context
    }
}
