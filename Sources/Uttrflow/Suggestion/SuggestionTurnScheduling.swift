import Foundation
import UttrflowPredict

/// Owns the delayed wake and the running turn without deciding whether suggestions may run.
@MainActor
final class SuggestionTurnScheduling {
    var turns = TurnGate()
    var state = SuggestionWakeState()
    var runningTurn: Int?
    private(set) var pendingWake: Task<Void, Never>?
    private var pendingWakeGeneration = 0
    private(set) var running: Task<Void, Never>?
    private let sleep: @Sendable (Duration) async throws -> Void

    init(sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    var hasPendingWake: Bool { pendingWake != nil }

    func wake(
        _ reason: SuggestionReason, afterMilliseconds delay: Int,
        wake: @escaping @MainActor (SuggestionReason) -> Void
    ) {
        cancelPendingWake()
        pendingWakeGeneration += 1
        let generation = pendingWakeGeneration
        pendingWake = Task { [weak self, sleep] in
            try? await sleep(.milliseconds(max(delay, 1)))
            guard !Task.isCancelled, self?.pendingWakeGeneration == generation else { return }
            self?.pendingWake = nil
            wake(reason)
        }
    }

    func cancelPendingWake() {
        pendingWakeGeneration += 1
        pendingWake?.cancel()
        pendingWake = nil
    }

    func wake(
        _ reason: SuggestionReason, at now: ContinuousClock.Instant,
        stalled: () -> Void,
        run: @escaping @MainActor (Int, SuggestionReason) async -> Void,
        next: @escaping @MainActor (SuggestionReason) -> Void
    ) {
        switch turns.begin(at: now) {
        case .busy:
            // A Return or a switch waiting its turn is never overwritten by the tick that follows it.
            _ = state.queue(reason)
        case .stalled(let turn):
            stalled()
            running?.cancel()
            start(turn, because: reason, run: run, next: next)
        case .free(let turn):
            start(turn, because: reason, run: run, next: next)
        }
    }

    private func start(
        _ turn: Int, because reason: SuggestionReason,
        run: @escaping @MainActor (Int, SuggestionReason) async -> Void,
        next: @escaping @MainActor (SuggestionReason) -> Void
    ) {
        runningTurn = turn
        running = Task { [weak self] in
            await run(turn, reason)
            self?.finished(turn, next: next)
        }
    }

    private func finished(_ turn: Int, next: @MainActor (SuggestionReason) -> Void) {
        if runningTurn == turn { runningTurn = nil }
        guard !state.isStopped, turns.end(turn), let nextReason = state.takeAfterTurn() else { return }
        next(nextReason)
    }

    func cancelRunning() { running?.cancel() }
}
