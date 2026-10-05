// Per-stage time limits, the Deadline that holds work to one, and the race that enforces it.

private import Synchronization

/// How long a dictation waits for one stage before giving up. See `Docs/stuck-recording.md`.
public enum StageTimeout: Sendable {
    /// Transcription, generous because a cold model load and four minutes of audio are both honest.
    public static let transcription = Duration.seconds(120)

    /// The whole tidying stage, as a backstop; each engine on the route has its own allowance inside it.
    public static let transformation = Duration.seconds(30)

    /// The router's whole route, every engine and the floor, kept inside the stage so the floor always answers.
    public static let route = Duration.seconds(28)

    /// What one model engine may take before the router steps past it, leaving the floor room inside the stage.
    public static let engine = Duration.seconds(20)

    /// What the deterministic floor may take; it only rearranges words already in hand.
    public static let rules = Duration.seconds(2)

    /// Context, correction, expansion and insertion: local, but each can block on another app.
    public static let quick = Duration.seconds(15)

    /// Loading the speech model: about twice the slowest measured cold load, 154 s. See `Docs/startup.md`.
    public static let speechModelLoad = Duration.seconds(300)
}

/// A point in time on an injected clock, after which waiting on work stops.
public struct Deadline: Sendable {
    /// How long the work was given when the deadline was set.
    public let allowance: Duration
    private let clock: any Clock<Duration>
    private let elapsed: @Sendable () -> Duration

    /// A deadline `allowance` from now on `clock`.
    public init(_ allowance: Duration, clock: any Clock<Duration> = ContinuousClock()) {
        self.allowance = allowance
        self.clock = clock
        self.elapsed = Self.stopwatch(on: clock)
    }

    /// Reads the time since now on `clock`, keeping the clock's own instant type out of the stored value.
    private static func stopwatch<C: Clock<Duration>>(on clock: C) -> @Sendable () -> Duration {
        let start = clock.now
        return { start.duration(to: clock.now) }
    }

    /// The time left, never below zero.
    public var remaining: Duration { max(.zero, allowance - elapsed()) }

    /// Whether the allowance has run out.
    public var isSpent: Bool { remaining == .zero }

    /// Runs `work`, answering `nil` when the deadline wins; the work is cancelled then, not awaited, since it may hang.
    public func race<Success: Sendable>(
        _ work: @escaping @Sendable () async throws -> Success
    ) async throws -> Success? {
        let race = StageRace<Success>()
        let limit = remaining
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                race.arm(continuation)
                race.start(clock: clock, limit: limit, work: work)
            }
        } onCancel: {
            race.finish(.cancelled)
        }
        return try race.result()
    }
}

/// Runs `work` against a `Deadline` of `limit` on `clock`, answering `nil` when the limit wins.
public func withStageTimeout<Success: Sendable>(
    _ limit: Duration,
    clock: any Clock<Duration>,
    _ work: @escaping @Sendable () async throws -> Success
) async throws -> Success? {
    try await Deadline(limit, clock: clock).race(work)
}

/// The work's answer if it arrives within `allowance` (at least 1 ms), else `nil`, the work cancelled and not awaited.
public func withDeadline<Answer: Sendable>(
    _ allowance: Duration,
    clock: any Clock<Duration> = ContinuousClock(),
    _ work: @escaping @Sendable () async -> Answer?
) async -> Answer? {
    let answer = try? await Deadline(max(allowance, .milliseconds(1)), clock: clock).race { await work() }
    return answer ?? nil
}

/// Whichever of a stage and its limit answered first, and what it answered.
private final class StageRace<Success: Sendable>: Sendable {
    /// What the winner answered.
    enum Outcome: Sendable {
        case finished(Success)
        case failed(any Error)
        case expired
        case cancelled
    }

    /// The waiting caller and the first answer, kept together under one lock.
    private struct State {
        var waiting: CheckedContinuation<Void, Never>?
        var outcome: Outcome?
        var timer: Task<Void, Never>?
        var working: Task<Void, Never>?
    }

    private let state = Mutex(State())

    /// Parks the caller until the first answer.
    func arm(_ continuation: CheckedContinuation<Void, Never>) {
        let resume = state.withLock { state -> Bool in
            guard state.outcome == nil else { return true }
            state.waiting = continuation
            return false
        }
        if resume { continuation.resume() }
    }

    /// Starts both racers, cancelling tasks immediately when an outcome already won.
    func start(
        clock: any Clock<Duration>, limit: Duration,
        work: @escaping @Sendable () async throws -> Success
    ) {
        state.withLock { state in
            guard state.outcome == nil else { return }
            state.working = Task {
                do { finish(.finished(try await work())) } catch { finish(.failed(error)) }
            }
            state.timer = Task { [clock] in
                try? await clock.sleep(for: limit)
                guard !Task.isCancelled else { return }
                finish(.expired)
            }
        }
    }

    /// Records an answer, and wakes the caller for the first one only.
    func finish(_ outcome: Outcome) {
        let completed = state.withLock {
            state -> (CheckedContinuation<Void, Never>?, Task<Void, Never>?, Task<Void, Never>?)? in
            guard state.outcome == nil else { return nil }
            state.outcome = outcome
            let completed = (state.waiting, state.timer, state.working)
            state.waiting = nil
            state.timer = nil
            state.working = nil
            return completed
        }
        guard let (waiting, timer, working) = completed else { return }
        timer?.cancel()
        working?.cancel()
        waiting?.resume()
    }

    /// The value, the error rethrown, or `nil` when the limit won.
    func result() throws -> Success? {
        switch state.withLock({ $0.outcome }) {
        case .finished(let value): value
        case .failed(let error): throw error
        case .expired, .cancelled, nil: nil
        }
    }
}
