// Collects samples from the capture thread and keeps the level meter's figures.
private import Synchronization

/// Collects samples from the capture thread in a lock-guarded box, since a real-time thread cannot await.
public final class SampleAccumulator: Sendable {
    private struct State {
        /// Blocks that are full and are never written to again, so a reader may hold them.
        var sealed: [[Float]] = []
        /// The one block the capture thread appends into, kept uniquely referenced so it grows in place.
        var open = State.opened()
        var count = 0
        var peak: Float = 0
        var momentary: Float = 0
        /// Whether a block has arrived since the meter last read, which is how a dead microphone shows up.
        var heardSinceRead = false
        /// Samples the capture thread has had to copy because storage moved under it. See Docs/audio-capture.md.
        var copiedOnAppend = 0

        /// Starts an empty block with room for a whole block, so appending into it never reallocates.
        static func opened() -> [Float] {
            var block = [Float]()
            block.reserveCapacity(SampleAccumulator.blockSize)
            return block
        }
    }

    /// Per-block release of the momentary level, blocks being the only clock here. See Docs/audio-capture.md.
    private static let release: Float = 0.62

    /// Samples per storage block, a quarter of a second of canonical audio. See Docs/audio-capture.md.
    static let blockSize = 4096

    private let state = Mutex(State())

    public init() {}

    /// Appends a block of samples and updates both levels.
    public func append(_ block: [Float]) {
        guard !block.isEmpty else { return }
        state.withLock { state in
            Self.store(block, into: &state)
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
            state.heardSinceRead = true
        }
    }

    /// Fills the open block, sealing it and opening another whenever it runs out of room.
    private static func store(_ block: [Float], into state: inout State) {
        state.count += block.count
        var remaining = block[...]
        while !remaining.isEmpty {
            if state.open.count == blockSize {
                let full = state.open
                state.open = State.opened()
                state.sealed.append(full)
            }
            let taken = Swift.min(blockSize - state.open.count, remaining.count)
            let before = state.open.count
            let address = state.open.withUnsafeBufferPointer { $0.baseAddress }
            state.open.append(contentsOf: remaining.prefix(taken))
            if state.open.withUnsafeBufferPointer({ $0.baseAddress }) != address {
                state.copiedOnAppend += before
            }
            remaining = remaining.dropFirst(taken)
        }
    }

    /// Number of samples collected so far.
    public var count: Int { state.withLock(\.count) }

    /// A copy of everything collected so far, leaving the capture thread's own block uniquely its own.
    public var snapshot: [Float] {
        let (sealed, open, total) = state.withLock { state in
            // Copied out rather than referenced, so the capture thread keeps sole ownership of it.
            (state.sealed, state.open.withUnsafeBufferPointer { [Float]($0) }, state.count)
        }
        return Self.joined(sealed, open, total)
    }

    /// Lays the blocks end to end into one array, which is the shape every reader downstream wants.
    private static func joined(_ sealed: [[Float]], _ open: [Float], _ total: Int) -> [Float] {
        var samples = [Float]()
        samples.reserveCapacity(total)
        for block in sealed { samples.append(contentsOf: block) }
        samples.append(contentsOf: open)
        return samples
    }

    /// Loudest sample since the last ``reset()``, in `0...1`; says afterwards whether the mic was muted.
    public var peakLevel: Float { state.withLock(\.peak) }

    /// How many samples the capture thread has copied because its storage moved, which the design keeps at zero.
    var copiedOnAppend: Int { state.withLock(\.copiedOnAppend) }

    /// How loud the microphone is now as RMS, in `0...1`, released on a read that no block arrived for.
    public var momentaryLevel: Float {
        state.withLock { state in
            // A microphone that stopped delivering would otherwise hold its last reading for ever.
            if state.heardSinceRead {
                state.heardSinceRead = false
            } else {
                state.momentary *= Self.release
            }
            return state.momentary
        }
    }

    /// Returns everything collected and clears the buffer, so a finished recording cannot leak into the next.
    public func take() -> [Float] {
        let (sealed, open, total) = state.withLock { state in
            defer { state = State() }
            return (state.sealed, state.open, state.count)
        }
        return Self.joined(sealed, open, total)
    }

    /// Discards everything collected.
    public func reset() {
        state.withLock { $0 = State() }
    }
}
