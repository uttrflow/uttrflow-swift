// What a pass was told about the moment, kept briefly so two passes about one line ask the machine once.

import Foundation
import UttrflowContext
import UttrflowPredict

/// Holds the context of the turn in hand, so the alternatives pass and an unchanged window cost no second walk.
actor SuggestionContextCache {
    /// How long a window's surroundings are believed; long enough for one turn, short enough to follow the screen.
    static let surroundingsLifetime = Duration.seconds(1)

    private var built: (turn: Int, situation: GenerationSituation)?
    private var walked: (key: String, surroundings: Surroundings, at: ContinuousClock.Instant)?
    private struct Walking {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Surroundings?, Never>]
    }
    private var walking: [String: Walking] = [:]

    /// What this turn was already told, when it has been told anything.
    func situation(forTurn turn: Int) -> GenerationSituation? {
        built?.turn == turn ? built?.situation : nil
    }

    /// Keeps this turn's context, replacing the turn before it.
    func remember(_ situation: GenerationSituation, forTurn turn: Int) {
        built = (turn, situation)
    }

    /// The window's surroundings, walked only when this window has not been walked lately and is not being walked now.
    func surroundings(
        for key: String, now: ContinuousClock.Instant = ContinuousClock().now,
        finishTime: @escaping @Sendable () -> ContinuousClock.Instant = { .now },
        reading walk: @escaping @Sendable () async -> Surroundings?
    ) async -> Surroundings? {
        if let walked, walked.key == key, now - walked.at < Self.surroundingsLifetime {
            return walked.surroundings
        }
        if let walking = walking[key] {
            return await waitForWalk(key, flight: walking.id)
        }
        let id = UUID()
        let task = Task {
            let fresh = await walk()
            finishWalk(key, flight: id, result: fresh, at: finishTime())
        }
        walking[key] = Walking(id: id, task: task, waiters: [:])
        return await waitForWalk(key, flight: id)
    }

    /// Waits for the shared flight; a cancelled caller leaves it running while another caller still needs it.
    private func waitForWalk(_ key: String, flight id: UUID) async -> Surroundings? {
        let waiter = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard var walking = walking[key], walking.id == id else {
                    continuation.resume(returning: nil)
                    return
                }
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    if walking.waiters.isEmpty {
                        walking.task.cancel()
                        self.walking[key] = nil
                    }
                    return
                }
                walking.waiters[waiter] = continuation
                self.walking[key] = walking
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiter, key: key, flight: id) }
        }
    }

    /// Removes a cancelled caller and cancels the flight only when no caller remains.
    private func cancelWaiter(_ waiter: UUID, key: String, flight id: UUID) {
        guard var walking = walking[key], walking.id == id,
            let continuation = walking.waiters.removeValue(forKey: waiter)
        else { return }
        continuation.resume(returning: nil)
        if walking.waiters.isEmpty {
            walking.task.cancel()
            self.walking[key] = nil
        } else {
            self.walking[key] = walking
        }
    }

    /// Publishes a completed walk once, timestamping the cache at completion rather than request start.
    private func finishWalk(
        _ key: String, flight id: UUID, result: Surroundings?, at finishedAt: ContinuousClock.Instant
    ) {
        guard let walking = walking[key], walking.id == id else { return }
        self.walking[key] = nil
        let answer = walking.task.isCancelled || walking.waiters.isEmpty ? nil : result
        if let answer { walked = (key, answer, finishedAt) }
        for continuation in walking.waiters.values { continuation.resume(returning: answer) }
    }
}
