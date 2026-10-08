// Deterministic loud and quiet variants of one clip, for measuring accuracy against input gain.

/// One level a clip is replayed at: scaled to a peak, or amplified and hard-clipped at full scale.
public enum InputLevel: Sendable, Equatable, CustomStringConvertible {
    /// The clip scaled so its peak sits at this many dBFS, with nothing clipped.
    case peak(decibels: Double)
    /// The clip, first scaled to a 0 dBFS peak, multiplied by this gain and clamped to `-1...1`.
    case clipped(gain: Float)

    /// The levels the gain sweep replays every passage at, from quietest to hottest.
    public static let sweep: [InputLevel] =
        [-40, -30, -20, -10, 0].map { .peak(decibels: $0) }
        + [2, 4, 8].map { .clipped(gain: $0) }

    public var description: String {
        switch self {
        case .peak(let decibels): "\(Int(decibels)) dBFS"
        case .clipped(let gain): "\(Int(gain))x clipped"
        }
    }

    /// `samples` at this level; silence stays silent.
    public func applied(to samples: [Float]) -> [Float] {
        switch self {
        case .peak(let decibels):
            return CueBleed.scaled(samples, toPeakDecibels: decibels)
        case .clipped(let gain):
            return CueBleed.scaled(samples, toPeakDecibels: 0).map { min(1, max(-1, $0 * gain)) }
        }
    }
}
