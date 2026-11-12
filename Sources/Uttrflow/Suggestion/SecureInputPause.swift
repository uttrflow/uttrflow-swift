import Foundation
import OSLog
import UttrflowInput

/// What a change in secure keyboard entry does to suggestions, carried out by the coordinator.
struct SecureInputPauseEffects {
    /// Secure entry began: take the ghost and the tap away, and say why.
    let paused: @MainActor () -> Void
    /// Secure entry ended: bring the tap back.
    let resumed: @MainActor () -> Void
}

/// Pauses suggestions while secure keyboard entry is on, and rechecks on a timer so the pause lifts in the same app without an activation.
@MainActor
final class SecureInputPause {
    /// Starts a check repeating at `interval` and returns what stops it, so a test decides when each recheck runs.
    typealias Scheduling =
        @MainActor (_ interval: TimeInterval, _ check: @escaping @MainActor () -> Void) -> @MainActor () -> Void

    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "predict")

    private let watch: SecureInputWatch
    private let schedule: Scheduling
    private var stopRecheck: (@MainActor () -> Void)?

    /// Whether the last check found secure input on.
    var isBlocking: Bool { watch.isBlocking }
    /// Whether a recheck is waiting to lift the pause.
    var isRecheckScheduled: Bool { stopRecheck != nil }

    init(watch: SecureInputWatch, schedule: @escaping Scheduling = SecureInputPause.recheckTimer) {
        self.watch = watch
        self.schedule = schedule
    }

    /// Checks once and, only when the answer changed, pauses or resumes; a pause keeps rechecking unless `mayRecheck` is false.
    func check(mayRecheck: Bool, effects: SecureInputPauseEffects) {
        guard watch.check() else { return }
        let now = watch.isBlocking ? "on" : "off"
        Self.log.notice("suggestion secure keyboard entry \(now, privacy: .public)")
        if watch.isBlocking {
            effects.paused()
            guard stopRecheck == nil, mayRecheck else { return }
            stopRecheck = schedule(SuggestionTicking.interval) { [weak self] in
                self?.check(mayRecheck: mayRecheck, effects: effects)
            }
        } else {
            stopRechecking()
            effects.resumed()
        }
    }

    /// Stops the recheck, so a stopped coordinator is never woken by it.
    func stopRechecking() {
        stopRecheck?()
        stopRecheck = nil
    }

    /// Runs `check` every `interval` on the main run loop and returns what stops it.
    static func recheckTimer(
        every interval: TimeInterval, _ check: @escaping @MainActor () -> Void
    ) -> @MainActor () -> Void {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { check() }
        }
        timer.tolerance = SuggestionTicking.tolerance
        return { timer.invalidate() }
    }
}
