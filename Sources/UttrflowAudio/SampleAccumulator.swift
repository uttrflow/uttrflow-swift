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
        var momentary: Float = 0
    }

    /// How much of the momentary level survives a block in which nothing was said.
    ///
    /// Attack is immediate and release is gradual, which is what every level meter
    /// does: a syllable has to appear the instant it arrives, and the fall between
    /// syllables has to be slow enough to see. Applied per block rather than per second
    /// because blocks are the only clock this type has — one arrives roughly every
    /// 85 ms at the tap's 4096 frames — and a decay measured in wall time would need a
    /// timestamp the capture thread should not be asked for.
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
            // Root mean square, not the block's peak: a meter driven by peaks reads
            // every click and lip smack as speech, which is exactly the twitchiness
            // that makes an animated meter look like it is not listening to anything.
            let rms = (sumOfSquares / Float(block.count)).squareRoot()
            let released = state.momentary * Self.release
            state.momentary = rms.isFinite ? Swift.max(rms, released) : released
        }
    }

    /// Number of samples collected so far.
    public var count: Int { state.withLock(\.samples.count) }

    /// A copy of everything collected so far, leaving the buffer as it is.
    public var snapshot: [Float] { state.withLock(\.samples) }

    /// Loudest sample seen since the last ``reset()``, in `0...1`.
    ///
    /// Drives the recording meter, and tells the CLI whether the microphone actually
    /// heard anything or was muted.
    public var peakLevel: Float { state.withLock(\.peak) }

    /// How loud the microphone is *now*, in `0...1`, as root mean square.
    ///
    /// Distinct from ``peakLevel``, which is a high-water mark and never falls — useful
    /// for asking afterwards whether the microphone was muted, useless for drawing a
    /// meter, because one loud syllable would peg it for the rest of the recording. The
    /// floating button reads this one.
    public var momentaryLevel: Float { state.withLock(\.momentary) }

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
