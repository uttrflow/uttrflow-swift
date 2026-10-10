// When tab-to-complete's clock observes a field, so an idle Mac is not woken needlessly.

import Foundation
import UttrflowPredictCapture

/// Runs the pause clock from an activity until a quiet window passes with nothing drawn. See `Docs/performance-suggestions.md`.
struct SuggestionTicking: Sendable, Equatable {
    /// How often the field is re-read while the clock runs.
    static let interval: TimeInterval = 1
    /// How often a still-visible ghost keeps the live field under observation after idle.
    static let ghostInterval: TimeInterval = 5
    /// How often an armed ghost's caret is checked while the person is active.
    static let activeSelectionInterval: TimeInterval = 0.2
    /// How far the system may move a tick to coalesce it with other wakeups.
    static let tolerance: TimeInterval = 0.2
    /// How long the clock runs after the last activity: past the idle commit, so that commit is still made.
    static let window: TimeInterval = CommitDetector.idleInterval + 4

    private var lastActivity: Date?
    private enum Phase: Sendable, Equatable {
        case stopped
        case active
        case watchingGhost
    }
    private var phase = Phase.stopped

    enum Tick: Equatable {
        case wake
        case wakeAndSlow
        case stop
    }

    var isRunning: Bool { phase != .stopped }

    /// How often an armed ghost's caret is checked: every 200 ms while active, every 5 s once a visible ghost has gone idle.
    var selectionInterval: TimeInterval {
        phase == .watchingGhost ? Self.ghostInterval : Self.activeSelectionInterval
    }

    /// Records a keystroke, click, switch or acceptance, answering whether the clock must be started for it.
    mutating func noteActivity(at moment: Date) -> Bool {
        lastActivity = moment
        guard phase != .active else { return false }
        phase = .active
        return true
    }

    /// Slows observation while a ghost remains visible, then stops when it is no longer relevant.
    mutating func tick(at moment: Date, ghostIsVisible: Bool) -> Tick {
        switch phase {
        case .stopped:
            return .stop
        case .active:
            guard let lastActivity, moment.timeIntervalSince(lastActivity) > Self.window else {
                return .wake
            }
            guard ghostIsVisible else {
                phase = .stopped
                return .stop
            }
            phase = .watchingGhost
            return .wakeAndSlow
        case .watchingGhost:
            guard ghostIsVisible else {
                phase = .stopped
                return .stop
            }
            return .wake
        }
    }
}
