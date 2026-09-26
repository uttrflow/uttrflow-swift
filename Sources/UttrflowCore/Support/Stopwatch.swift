/// Opens the existential clock, which is what lets an instant be held on to.
public func stopwatch(from clock: some Clock<Duration>) -> () -> Duration {
    let start = clock.now
    return { start.duration(to: clock.now) }
}
