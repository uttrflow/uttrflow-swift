// The bounded wait that lets a tap hand over its last block before the engine is torn down.
private import Synchronization

/// Gives a microphone tap one buffer period at key-up to deliver the block the hardware is still filling.
public final class TapDrain: Sendable {
    /// A device that misreports its rate must not hold key-up open, so no drain ever waits longer than this.
    public static let cap: Duration = .milliseconds(250)

    private let step: Duration
    private let pause: @Sendable (Duration) async throws -> Void
    private let blocks = Mutex(0)

    public init(
        step: Duration = .milliseconds(5),
        pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.step = step
        self.pause = pause
    }

    /// One tap period, sized from the buffer the tap was installed with and the rate the device runs at.
    public static func window(tapFrames: Int, sampleRate: Double) -> Duration {
        guard tapFrames > 0, sampleRate > 0 else { return .zero }
        return min(cap, .seconds(Double(tapFrames) / sampleRate))
    }

    /// Counted on the capture thread, because a delivered block is the only sign the tap handed anything over.
    public func blockDelivered() {
        blocks.withLock { $0 += 1 }
    }

    /// How many blocks the tap has delivered since this drain was made.
    public var deliveredCount: Int { blocks.withLock { $0 } }

    /// Returns as soon as one more block arrives, and at the latest when the window closes.
    public func wait(_ window: Duration) async {
        guard window > .zero else { return }
        let before = blocks.withLock { $0 }
        var waited = Duration.zero
        while waited < window {
            let slice = min(step, window - waited)
            guard (try? await pause(slice)) != nil else { return }
            waited += slice
            if blocks.withLock({ $0 }) != before { return }
        }
    }
}
