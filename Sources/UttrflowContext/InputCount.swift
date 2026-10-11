private import Synchronization

/// Counts keys and clicks by asking, each time it is read, how long ago the last one came.
final class InputCount: Sendable {
    /// How long ago the system last saw a key or a click.
    private let sinceLastInput: @Sendable () -> Duration
    /// The time since this count began, on the injected clock.
    private let now: @Sendable () -> Duration
    /// The count so far, and the time of its latest reading.
    private let state = Mutex<(count: Int, lastRead: Duration?)>((0, nil))

    /// A count that tells time on `clock`, which must run at the same rate as the system's input clock.
    init(
        clock: some Clock<Duration> = ContinuousClock(),
        sinceLastInput: @escaping @Sendable () -> Duration
    ) {
        self.sinceLastInput = sinceLastInput
        let start = clock.now
        now = { start.duration(to: clock.now) }
    }

    /// The count, one higher than at the last reading when a key or a click has come since it.
    var value: Int {
        let now = now()
        let since = sinceLastInput()
        return state.withLock { state in
            if let lastRead = state.lastRead, since < now - lastRead { state.count += 1 }
            state.lastRead = now
            return state.count
        }
    }
}
