// The one fixed-seed generator, for any draw that must come out the same on every run.

/// An xorshift generator whose whole sequence is set by its seed.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    /// A generator that always produces the same sequence for the same seed.
    public init(seed: UInt64) {
        // The multiply spreads small seeds apart and the low bit keeps xorshift out of its zero fixed point.
        state = (seed &* 0x9E37_79B9_7F4A_7C15) | 1
    }

    /// The next value in the sequence.
    public mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
