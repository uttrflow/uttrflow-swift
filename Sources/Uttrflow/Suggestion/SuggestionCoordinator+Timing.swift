import Foundation
import UttrflowPredict

extension SuggestionCoordinator {
    /// Elapsed key time never goes below zero when the system wall clock moves backwards.
    nonisolated static func elapsedMilliseconds(since earlier: Date, at later: Date) -> Int {
        max(0, Int(later.timeIntervalSince(earlier) * 1000))
    }

    /// Milliseconds until the prose pause after the latest keystroke is long enough, counted from now rather than from the turn's start.
    nonisolated static func hesitationWake(sinceKeystroke keystroke: Date, now: Date) -> Int {
        let passed = max(0, Int(now.timeIntervalSince(keystroke) * 1000))
        return max(0, Quieting.proseHesitationInMilliseconds - passed) + 20
    }

    /// What is left of the debounce for a key pressed at `keystroke`, which is nothing once the pause is long enough.
    nonisolated static func remainingDebounce(sinceKeystroke keystroke: Date, now: Date) -> Duration {
        let passed = max(0, now.timeIntervalSince(keystroke) * 1000)
        return .milliseconds(max(0, Double(Self.generationDebounceInMilliseconds) - passed))
    }

    /// Milliseconds left before typing has paused long enough to read the field.
    nonisolated static func remainingFieldReadDebounce(sinceKeystroke keystroke: Date, now: Date) -> Int {
        let passed = max(0, now.timeIntervalSince(keystroke) * 1000)
        let remaining = Double(Self.fieldReadDebounceInMilliseconds) - passed
        return remaining <= 0.001 ? 0 : Int(ceil(remaining - 0.001))
    }

    /// How long this turn has taken, which is what decides whether its answer is still worth drawing.
    nonisolated static func elapsedMilliseconds(
        since started: ContinuousClock.Instant, now: ContinuousClock.Instant
    ) -> Int {
        let elapsed = started.duration(to: now).components
        let milliseconds = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
        return Int(max(0, milliseconds))
    }
}
