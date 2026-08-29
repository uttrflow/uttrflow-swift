private import Synchronization

/// Collects audio samples arriving from the capture thread.
///
/// A microphone tap runs on a real-time thread that must never wait on an actor, so
/// this is a plain lock-guarded box rather than an actor. The lock is uncontended in
/// practice — one producer, one consumer, never at the same moment.
public final class SampleAccumulator: Sendable {
    private struct State {
        var samples: [Float] = []
        var peak: Float = 0
    }

    private let state = Mutex(State())

    public init() {}

    /// Appends a block of samples and updates the running peak.
    public func append(_ block: [Float]) {
        guard !block.isEmpty else { return }
        state.withLock { state in
            state.samples.append(contentsOf: block)
            for sample in block {
                let magnitude = Swift.abs(sample)
                if magnitude.isFinite, magnitude > state.peak { state.peak = magnitude }
            }
        }
    }

    /// Number of samples collected so far.
    public var count: Int { state.withLock(\.samples.count) }

    /// Loudest sample seen since the last ``reset()``, in `0...1`.
    ///
    /// Drives the recording meter, and tells the CLI whether the microphone actually
    /// heard anything or was muted.
    public var peakLevel: Float { state.withLock(\.peak) }

    /// Returns everything collected and clears the buffer, so a finished recording
    /// cannot leak into the next one.
    public func take() -> [Float] {
        state.withLock { state in
            defer { state = State() }
            return state.samples
        }
    }

    /// Discards everything collected.
    public func reset() {
        state.withLock { $0 = State() }
    }
}
