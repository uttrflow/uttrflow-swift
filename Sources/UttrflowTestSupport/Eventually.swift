// Waits a test makes on work running beside it, which end on a signal or a condition rather than a clock.

/// Thrown when a wait ends because its task was cancelled, which a suite's time limit does to a wait that never ends.
public struct WaitNeverEnded: Error, CustomStringConvertible {
    public let description = "the awaited condition never held before the test was cancelled"
}

/// Yields until `condition` holds, throwing once the task is cancelled; the suite's `.timeLimit` ends a wait that never does.
public func eventually(
    isolation: isolated (any Actor)? = #isolation, _ condition: () async -> Bool
) async throws(WaitNeverEnded) {
    while !(await condition()) {
        if Task.isCancelled { throw WaitNeverEnded() }
        await Task.yield()
    }
}

/// Suspends until `signal` fires once, throwing if the task is cancelled or the signal finishes first.
public func arrival(of signal: AsyncStream<Void>) async throws(WaitNeverEnded) {
    for await _ in signal { return }
    throw WaitNeverEnded()
}

/// A one-way signal a test double fires when it reaches a point a test waits for.
public struct Signal: Sendable {
    /// What a test waits on, which buffers a fire that happens before anyone waits.
    public let fired: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    public init() {
        (fired, continuation) = AsyncStream.makeStream()
    }

    /// Marks the point as reached.
    public func fire() { continuation.yield() }
}
