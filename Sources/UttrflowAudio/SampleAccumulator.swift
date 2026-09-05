private import Synchronization

/// Collects samples from the capture thread in a lock-guarded box, since a real-time thread cannot await.
public final class SampleAccumulator: Sendable {
    private struct State {
        var samples: [Float] = []
        var peak: Float = 0
        var momentary: Float = 0
    }

    /// Per-block release of the momentary level, blocks being the only clock here. See Docs/audio-capture.md.
    private static let release: Float = 0.62

    private let state = Mutex(State())

    public init() {}

    /// Appends a block of samples and updates both levels.
    public func append(_ block: [Float]) {
        guard !block.isEmpty else { return }
        state.withLock { state in
            state.samples.append(contentsOf: block)
            var sumOfSquares: Float = 0
            for sample in block {
                let magnitude = Swift.abs(sample)
                guard magnitude.isFinite else { continue }
                if magnitude > state.peak { state.peak = magnitude }
                sumOfSquares += sample * sample
            }
            // Root mean square, not the peak, so clicks and lip smacks do not make the meter twitch.
            let rms = (sumOfSquares / Float(block.count)).squareRoot()
            let released = state.momentary * Self.release
            state.momentary = rms.isFinite ? Swift.max(rms, released) : released
        }
    }

    /// Number of samples collected so far.
    public var count: Int { state.withLock(\.samples.count) }

    /// A copy of everything collected so far, leaving the buffer as it is.
    public var snapshot: [Float] { state.withLock(\.samples) }

    /// Loudest sample since the last ``reset()``, in `0...1`; says afterwards whether the mic was muted.
    public var peakLevel: Float { state.withLock(\.peak) }

    /// How loud the microphone is now as RMS, in `0...1`; the meter reads this, not the high-water mark.
    public var momentaryLevel: Float { state.withLock(\.momentary) }

    /// Returns everything collected and clears the buffer, so a finished recording cannot leak into the next.
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
