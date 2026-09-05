// Per-stage time limits, and the race that enforces one without waiting on a stage that hangs.

private import Synchronization

/// How long a dictation waits for one stage before giving up. See `Docs/stuck-recording.md`.
public enum StageTimeout: Sendable {
    /// Transcription, generous because a cold model load and four minutes of audio are both honest.
    public static let transcription = Duration.seconds(120)

    /// Tidying, which is a language model reading one utterance.
    public static let transformation = Duration.seconds(30)

    /// Context, correction, expansion and insertion: local, but each can block on another app.
    public static let quick = Duration.seconds(15)
}

/// Runs `work`, answering `nil` when `limit` wins; the work is abandoned, not awaited, since it may hang.
public func withStageTimeout<Success: Sendable>(
    _ limit: Duration,
    clock: any Clock<Duration>,
    _ work: @escaping @Sendable () async throws -> Success
) async throws -> Success? {
    let race = StageRace<Success>()
    var timer: Task<Void, Never>?
    await withCheckedContinuation { continuation in
        // Armed before either racer exists, so neither can arrive at an empty race.
        race.arm(continuation)
        Task {
            do { race.finish(.finished(try await work())) } catch { race.finish(.failed(error)) }
        }
        timer = Task { [clock] in
            try? await clock.sleep(for: limit)
            race.finish(.expired)
        }
    }
    // Cancelled so a stage that answers in time leaves no task waiting out the limit.
    timer?.cancel()
    return try race.result()
}

/// Whichever of a stage and its limit answered first, and what it answered.
private final class StageRace<Success: Sendable>: Sendable {
    /// What the winner answered.
    enum Outcome: Sendable {
        case finished(Success)
        case failed(any Error)
        case expired
    }

    /// The waiting caller and the first answer, kept together under one lock.
    private struct State {
        var waiting: CheckedContinuation<Void, Never>?
        var outcome: Outcome?
    }

    private let state = Mutex(State())

    /// Parks the caller until the first answer.
    func arm(_ continuation: CheckedContinuation<Void, Never>) {
        state.withLock { $0.waiting = continuation }
    }

    /// Records an answer, and wakes the caller for the first one only.
    func finish(_ outcome: Outcome) {
        let waiting = state.withLock { state -> CheckedContinuation<Void, Never>? in
            guard state.outcome == nil else { return nil }
            state.outcome = outcome
            defer { state.waiting = nil }
            return state.waiting
        }
        waiting?.resume()
    }

    /// The value, the error rethrown, or `nil` when the limit won.
    func result() throws -> Success? {
        switch state.withLock({ $0.outcome }) {
        case .finished(let value): value
        case .failed(let error): throw error
        // Only reachable if the caller resumed without an outcome, which cannot happen.
        case .expired, nil: nil
        }
    }
}
