// How long one read of the focused field may run, and how long a field that ran past it is left alone.

private import Synchronization
import UttrflowCore

/// One read's allowance in all, held by a `Deadline`, since each message's own timeout only stops the waiting. See `Docs/predict.md`.
enum FieldReadBudget {
    /// The whole read's allowance, under one message's timeout, since a field that answers at all answers in a few milliseconds.
    static let allowance = Duration.milliseconds(40)

    /// A deadline for one read starting now on `clock`, the uptime clock unless a test drives its own.
    static func start(on clock: any Clock<Duration> = SuspendingClock()) -> Deadline {
        Deadline(allowance, clock: clock)
    }
}

/// The fields whose last read ran past its budget, each left alone for a while so the application is not asked again every turn.
final class SlowFields: Sendable {
    /// One field of one application, as Accessibility hashes the element.
    struct Key: Hashable, Sendable {
        let process: Int32
        let element: UInt
    }

    /// How long a field is first left alone.
    static let firstRest = Duration.seconds(10)
    /// The longest a field is left alone, however often its reads run over.
    static let longestRest = Duration.seconds(300)
    /// How many fields are remembered at once, the oldest rest dropped first.
    static let capacity = 64

    /// When each resting field may be read again, and how long its last rest was, as time since this record began.
    private struct Rest {
        var until: Duration
        var length: Duration
    }

    /// Every field's rest, and each application quieted whole until its resting field may lose focus.
    private struct State {
        var rests: [Key: Rest] = [:]
        var quiet: [Int32: Duration] = [:]
    }

    private let state = Mutex(State())
    /// The time since this record began, on the injected clock.
    private let now: @Sendable () -> Duration

    /// A record that tells time on `clock`, the uptime clock unless a test drives its own.
    init(clock: any Clock<Duration> = SuspendingClock()) {
        now = Self.stopwatch(on: clock)
    }

    /// Reads the time since now on `clock`, keeping the clock's own instant type out of the stored value.
    private static func stopwatch<C: Clock<Duration>>(on clock: C) -> @Sendable () -> Duration {
        let start = clock.now
        return { start.duration(to: clock.now) }
    }

    /// Whether this field is still resting, when no message may be sent to it; one that is quiets its application again.
    func isResting(_ key: Key) -> Bool {
        let now = now()
        return state.withLock { state in
            guard let until = state.rests[key]?.until, until > now else { return false }
            state.quiet[key.process] = until
            return true
        }
    }

    /// Whether an application is quiet because its focused field rests, so not even its focus is asked for.
    func isQuiet(_ process: Int32) -> Bool {
        let now = now()
        return state.withLock { ($0.quiet[process] ?? .zero) > now }
    }

    /// Ends every application's quiet, since a click, a switch or a focus key may have left the resting field.
    func focusMayHaveMoved() {
        state.withLock { $0.quiet = [:] }
    }

    /// Records a read of this field that ran past its budget: the first is forgiven as a cold start, then the rest doubles up to the longest.
    func ranOver(_ key: Key) {
        let now = now()
        state.withLock { state in
            let length = state.rests[key].map(Self.nextRest) ?? .zero
            state.rests[key] = Rest(until: now + length, length: length)
            if length > .zero { state.quiet[key.process] = now + length }
            guard state.rests.count > Self.capacity,
                let oldest = state.rests.filter({ $0.key != key }).min(by: { $0.value.until < $1.value.until }
                )?
                .key
            else { return }
            state.rests[oldest] = nil
        }
    }

    /// The rest after one more overrun: the first rest after a forgiven one, then double the last, up to the longest.
    private static func nextRest(after rest: Rest) -> Duration {
        rest.length == .zero ? firstRest : min(rest.length * 2, longestRest)
    }

    /// Records a read of this field that kept to its budget, which ends any backing off.
    func answered(_ key: Key) {
        state.withLock { state in
            state.rests[key] = nil
            state.quiet[key.process] = nil
        }
    }
}
