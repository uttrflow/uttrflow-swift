import Foundation

/// Owns selection-check cadence and invalidation while the Coordinator decides when a read is allowed.
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
