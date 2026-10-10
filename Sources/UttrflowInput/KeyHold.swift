internal import CoreGraphics
internal import Synchronization

/// Keys pressed between a swallowed keystroke and its handling, kept back and replayed in order afterwards.
final class KeyHold: Sendable {
    /// How long a hold may last before keys pass through again, so a stalled handler never keeps the keyboard.
    static let limitNanoseconds: UInt64 = 1_000_000_000

    /// The active hold start and the key-downs waiting for its release.
    private struct State {
        var since: UInt64 = 0
        var kept: [Kept] = []
        var suppressUnarmedTab = false
    }
    private let state = Mutex(State())
    /// The time a hold is measured on, injected so a test can move it by hand.
    private let clock: ElapsedClock
    /// A copied event, owned by the hold alone from the moment it is kept.
    private struct Kept: @unchecked Sendable {
        let event: CGEvent
    }

    /// A hold measured on `clock`, the continuous clock unless a test passes its own.
    init(clock: some Clock<Duration> = ContinuousClock()) {
        self.clock = ElapsedClock(clock)
    }

    /// Starts holding keys back, from the moment a keystroke is swallowed on the tap's thread.
    func begin(suppressingUnarmedTab: Bool = false) {
        let now = clock.nanoseconds
        state.withLock {
            $0.since = now
            $0.suppressUnarmedTab = suppressingUnarmedTab
        }
    }

    /// Whether keys are being held back, which keeps the tap on while nothing is armed.
    var isHolding: Bool { state.withLock { $0.since != 0 } }

    /// Replays queued keys when the hold expires, so a delayed accept cannot discard typed input.
    func expireIfNeeded(
        post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
        where shouldPost: (CGEvent) -> Bool = { _ in true }
    ) -> Bool {
        let now = clock.nanoseconds
        let expiredEvents = state.withLock { state -> [Kept]? in
            guard state.since != 0, now &- state.since >= Self.limitNanoseconds else { return nil }
            state.since = 0
            state.suppressUnarmedTab = false
            let events = state.kept
            state.kept.removeAll()
            return events
        }
        guard let expiredEvents else { return false }
        for kept in expiredEvents where shouldPost(kept.event) { post(kept.event) }
        return true
    }

    /// Whether the swallowed key was bare Tab, which can leak as literal input during accept.
    var isHoldingBareTabAccept: Bool { state.withLock(\.suppressUnarmedTab) }

    /// Keeps a copy of a key-down back and returns true while a hold is in force; false lets it through.
    func keep(
        _ event: CGEvent,
        afterEligibilityCheck: () -> Void = {},
        postExpired: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
        where shouldPostExpired: (CGEvent) -> Bool = { _ in true }
    ) -> Bool {
        let now = clock.nanoseconds
        let (kept, expiredEvents) = state.withLock { state -> (Bool, [Kept]?) in
            let start = state.since
            guard start != 0 else { return (false, nil) }
            guard now &- start < Self.limitNanoseconds else {
                state.since = 0
                state.suppressUnarmedTab = false
                let events = state.kept
                state.kept.removeAll()
                return (false, events)
            }
            afterEligibilityCheck()
            guard let copy = event.copy() else { return (false, nil) }
            state.kept.append(Kept(event: copy))
            return (true, nil)
        }
        guard let expiredEvents else { return kept }
        for kept in expiredEvents where shouldPostExpired(kept.event) { postExpired(kept.event) }
        return kept
    }

    /// Ends the hold and hands each allowed key-down to `post`, oldest first.
    func release(
        post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
        where shouldPost: (CGEvent) -> Bool = { _ in true }
    ) {
        let events = state.withLock { state in
            state.since = 0
            state.suppressUnarmedTab = false
            defer { state.kept.removeAll() }
            return state.kept
        }
        for kept in events where shouldPost(kept.event) { post(kept.event) }
    }
}
