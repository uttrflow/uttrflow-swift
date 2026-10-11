import Foundation

/// Owns the activity timer and the phase it observes, without choosing when the loop may read.
@MainActor
final class SuggestionActivityClock {
    private var ticker: Timer?
    private var phase = SuggestionTicking()

    var isScheduled: Bool { ticker != nil }
    var isRunning: Bool { phase.isRunning }
    var selectionInterval: TimeInterval { phase.selectionInterval }

    /// Records activity through the existing phase rule.
    func noteActivity(at moment: ContinuousClock.Instant) -> Bool {
        phase.noteActivity(at: moment)
    }

    /// Advances the existing phase rule before the coordinator acts on its verdict.
    func tick(at moment: ContinuousClock.Instant, ghostIsVisible: Bool) -> SuggestionTicking.Tick {
        phase.tick(at: moment, ghostIsVisible: ghostIsVisible)
    }

    /// Invalidates the previous handle before its replacement is made.
    func schedule(creating create: () -> Timer) {
        ticker?.invalidate()
        ticker = create()
    }

    /// Stops the handle without resetting the phase.
    func suspend() {
        ticker?.invalidate()
        ticker = nil
    }

    /// Clears the handle before starting a fresh phase.
    func reset() {
        suspend()
        phase = SuggestionTicking()
    }
}
