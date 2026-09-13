// When tab-to-complete's clock runs, so an idle Mac is not woken to read a field nobody is using.

import Foundation
import UttrflowPredictCapture

/// Runs the pause clock from an activity until a quiet window passes with nothing drawn. See `Docs/performance.md`.
struct SuggestionTicking: Sendable, Equatable {
    /// How often the field is re-read while the clock runs.
    static let interval: TimeInterval = 1
    /// How far the system may move a tick to coalesce it with other wakeups.
    static let tolerance: TimeInterval = 0.2
    /// How long the clock runs after the last activity: past the idle commit, so that commit is still made.
    static let window: TimeInterval = CommitDetector.idleInterval + 4

    private var lastActivity: Date?
    private(set) var isRunning = false

    /// Records a keystroke, click, switch or acceptance, answering whether the clock must be started for it.
    mutating func noteActivity(at moment: Date) -> Bool {
        lastActivity = moment
        guard !isRunning else { return false }
        isRunning = true
        return true
    }

    /// Answers whether this tick wakes a turn; when it does not, the clock has stopped and must be invalidated.
    mutating func tick(at moment: Date, isShowing: Bool) -> Bool {
        guard isRunning, let lastActivity else { return false }
        guard isShowing || moment.timeIntervalSince(lastActivity) <= Self.window else {
            isRunning = false
            return false
        }
        return true
    }
}
