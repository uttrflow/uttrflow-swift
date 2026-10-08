/// Holds the wake a running turn owes, until it finishes or the loop stops.
struct SuggestionWakeState {
    private(set) var isStopped = false
    private var queued: SuggestionReason?

    /// Refuses a wake after stop and otherwise keeps the most urgent queued reason.
    mutating func queue(_ reason: SuggestionReason) -> Bool {
        guard !isStopped else { return false }
        if queued.map({ reason.urgency > $0.urgency }) ?? true { queued = reason }
        return true
    }

    /// Takes a queued wake after a turn, or refuses it once stopped.
    mutating func takeAfterTurn() -> SuggestionReason? {
        defer { queued = nil }
        guard !isStopped else { return nil }
        return queued
    }

    /// Clears a pending wake while preserving whether the loop is stopped.
    mutating func clearQueuedWake() { queued = nil }

    /// Stops the loop and discards the wake a running turn had queued.
    mutating func stop() {
        isStopped = true
        queued = nil
    }

    /// Reopens the loop for a fresh start with no wake carried from its previous run.
    mutating func start() {
        isStopped = false
        queued = nil
    }
}
