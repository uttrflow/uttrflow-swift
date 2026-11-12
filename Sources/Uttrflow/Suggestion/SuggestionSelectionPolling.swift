import Foundation
import UttrflowContext

/// Owns selection-check cadence, invalidation, and what each check's read means for the armed offer.
@MainActor
final class SuggestionSelectionPolling {
    private var stopChecks: (@MainActor () -> Void)?
    private var interval: TimeInterval?
    var guardrail: ArmedSelectionGuard?
    var isReadInFlight = false
    private(set) var generation = 0

    var isScheduled: Bool { stopChecks != nil }

    func start(
        every interval: TimeInterval, schedule: SelectionCheckScheduling,
        check: @escaping @MainActor (Int) -> Void
    ) {
        stopChecks?()
        let generation = generation
        self.interval = interval
        stopChecks = schedule(interval) { check(generation) }
    }

    func follow(
        every interval: TimeInterval, schedule: SelectionCheckScheduling,
        check: @escaping @MainActor (Int) -> Void
    ) {
        guard stopChecks != nil, self.interval != interval else { return }
        start(every: interval, schedule: schedule, check: check)
    }

    /// What one selection check found about the armed offer.
    enum Verdict: Equatable {
        /// Nothing to act on: the check is stale, a read is in flight, nothing is armed, or the read timed out.
        case keep
        /// The caret, the selection or the focused element moved, or suggestions are no longer allowed here.
        case withdraw
    }

    /// Reads the focused selection for `generation` and says whether the armed offer still stands.
    func check(
        generation: Int, isArmed: Bool, isInserting: Bool, isAllowed: () -> Bool,
        read: () async -> FocusedFieldSelectionRead
    ) async -> Verdict {
        guard generation == self.generation, !isReadInFlight, isArmed, guardrail != nil, !isInserting
        else { return .keep }
        guard isAllowed() else { return .withdraw }
        isReadInFlight = true
        let selection = await read()
        // A stop while the read was out voided it, and the stop already cleared the flag.
        guard generation == self.generation else { return .keep }
        isReadInFlight = false
        switch selection {
        case .timedOut:
            return .keep
        case .unavailable:
            return .withdraw
        case .selection(let value):
            guard var selectionGuard = guardrail else { return .keep }
            guard !selectionGuard.observe(value) else { return .withdraw }
            guardrail = selectionGuard
            return .keep
        }
    }

    func stop(cancelRead: () -> Void) {
        generation += 1
        stopChecks?()
        stopChecks = nil
        interval = nil
        guardrail = nil
        isReadInFlight = false
        cancelRead()
    }
}
