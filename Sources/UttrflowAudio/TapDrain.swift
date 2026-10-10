// The bounded wait that lets a tap hand over its last block before the engine is torn down.
private import Synchronization

/// Gives a microphone tap one buffer period at key-up to deliver the block the hardware is still filling.
public final class TapDrain: Sendable {
    /// A device that misreports its rate must not hold key-up open, so no drain ever waits longer than this.
    public static let cap: Duration = .milliseconds(250)

    private let step: Duration
    private let clock: any Clock<Duration>
    private let blocks = Mutex(0)
    private let lastBlock = Mutex(0)

    /// What one key-up wait took, so a drain can be timed per device instead of assumed from the window.
    public struct Outcome: Sendable, Equatable {
        /// Time slept before the wait returned, never more than the window.
        public let waited: Duration
        /// Whether a block arrived inside the window, rather than the window running out.
        public let arrived: Bool
        /// Samples in the most recent block delivered, after conversion, so a device that ignores the tap size shows.
        public let lastBlockSamples: Int
    }

    public init(
        step: Duration = .milliseconds(5),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.step = step
        self.clock = clock
    }

    /// One tap period, sized from the buffer the tap was installed with and the rate the device runs at.
    public static func window(tapFrames: Int, sampleRate: Double) -> Duration {
        guard tapFrames > 0, sampleRate > 0 else { return .zero }
        return min(cap, .seconds(Double(tapFrames) / sampleRate))
    }

    /// Counted on the capture thread, because a delivered block is the only sign the tap handed anything over.
    public func blockDelivered(samples: Int = 0) {
        lastBlock.withLock { $0 = samples }
        blocks.withLock { $0 += 1 }
    }

    /// How many blocks the tap has delivered since this drain was made.
    public var deliveredCount: Int { blocks.withLock { $0 } }

    /// Returns as soon as one more block arrives, and at the latest when the window closes.
    @discardableResult
    public func wait(_ window: Duration) async -> Outcome {
        let before = blocks.withLock { $0 }
        var waited = Duration.zero
        var arrived = false
        while waited < window, !arrived {
            let slice = min(step, window - waited)
            guard (try? await clock.sleep(for: slice)) != nil else { break }
            waited += slice
            arrived = blocks.withLock { $0 } != before
        }
        return Outcome(waited: waited, arrived: arrived, lastBlockSamples: lastBlock.withLock { $0 })
    }
}
