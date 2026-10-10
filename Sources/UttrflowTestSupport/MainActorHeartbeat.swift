// Watches whether the main actor keeps turning, so a test can fail on a stall no stage budget sees.

/// Beats on the main actor every millisecond and keeps the longest wall-clock gap between two beats.
@MainActor
public final class MainActorHeartbeat {
    private var lastBeat: ContinuousClock.Instant?
    private var task: Task<Void, Never>?

    /// The longest time the main actor went without letting a beat run, since ``start()``.
    public private(set) var longestGap: Duration = .zero

    public init() {}

    /// Starts beating; the first gap is measured from now.
    public func start() {
        lastBeat = .now
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1))
                self?.beat()
            }
        }
    }

    /// Stops beating and returns the longest gap, counting the one that ends now.
    public func stop() -> Duration {
        task?.cancel()
        task = nil
        beat()
        return longestGap
    }

    /// The longest gap while the main actor does nothing for `span`, which is what the host's load alone costs.
    public static func idleGap(over span: Duration = .milliseconds(200)) async -> Duration {
        let heartbeat = MainActorHeartbeat()
        heartbeat.start()
        try? await Task.sleep(for: span)
        return heartbeat.stop()
    }

    private func beat() {
        let now = ContinuousClock.now
        if let lastBeat { longestGap = max(longestGap, lastBeat.duration(to: now)) }
        lastBeat = now
    }
}
