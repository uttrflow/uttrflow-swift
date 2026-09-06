/// A fixed-seed generator, so every generated case is the same on every run and a failure names its seed.
struct Seeded: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        // The multiply spreads small seeds apart and the low bit keeps xorshift out of its zero fixed point.
        state = (UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15) | 1
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// One of the values, chosen uniformly.
    mutating func pick<Value>(_ values: [Value]) -> Value {
        values[Int.random(in: 0..<values.count, using: &self)]
    }

    /// Whether an event with this probability happens this time.
    mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1, using: &self) < probability
    }
}
