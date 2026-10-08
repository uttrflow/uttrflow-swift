/// A block of mono PCM audio normalised to `-1...1`, the one format every engine speaks.
public struct AudioSamples: Sendable, Equatable {
    /// The sample rate every speech engine in the product expects.
    public static let canonicalSampleRate = 16_000

    /// An empty buffer at the canonical rate, which is what a cancelled recording yields.
    public static let empty = AudioSamples(unchecked: [], sampleRate: canonicalSampleRate)

    /// The samples, in `-1...1`.
    public let samples: [Float]
    /// Samples per second.
    public let sampleRate: Int
    /// Ascending sample offsets where time passed that no sample carried, so audio either side is never joined.
    public let discontinuities: [Int]
    /// Holes the capture timeline saw in the whole recording, including those filled with silence.
    public let gaps: CaptureGaps

    /// Creates a buffer, rejecting a non-positive sample rate.
    public init?(samples: [Float], sampleRate: Int) {
        guard sampleRate > 0 else { return nil }
        self.init(unchecked: samples, sampleRate: sampleRate)
    }

    /// Stores a rate already known to be positive.
    private init(
        unchecked samples: [Float], sampleRate: Int, discontinuities: [Int] = [], gaps: CaptureGaps = .none
    ) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.discontinuities = discontinuities
        self.gaps = gaps
    }

    /// Wraps samples already at ``canonicalSampleRate``, without a `nil` branch that cannot happen.
    public static func canonical(
        _ samples: [Float], discontinuities: [Int] = [], gaps: CaptureGaps = .none
    ) -> AudioSamples {
        AudioSamples(
            unchecked: samples, sampleRate: canonicalSampleRate,
            discontinuities: Self.inside(discontinuities, count: samples.count), gaps: gaps)
    }

    /// The audio from sample `start` on, with each discontinuity still marking the same instant.
    public func dropping(first start: Int) -> AudioSamples {
        let from = Swift.min(Swift.max(0, start), samples.count)
        return AudioSamples(
            unchecked: Array(samples[from...]), sampleRate: sampleRate,
            discontinuities: Self.inside(discontinuities.map { $0 - from }, count: samples.count - from),
            gaps: gaps)
    }

    /// Keeps only the offsets with audio on both sides, in order and once each.
    private static func inside(_ offsets: [Int], count: Int) -> [Int] {
        Array(Set(offsets.filter { $0 > 0 && $0 < count })).sorted()
    }

    public var isEmpty: Bool { samples.isEmpty }

    /// Wall-clock length of the recording.
    public var duration: Duration {
        .seconds(Double(samples.count) / Double(sampleRate))
    }

    /// Below this magnitude a sample is digital silence; a quiet room's noise floor is far above it.
    static let noSignalPeak: Float = 1e-6

    /// Whether a second or more arrived with no signal at all: a muted input, a zero input level or a dead cable.
    public var carriesNoSignal: Bool {
        duration >= .seconds(1) && samples.allSatisfy { Swift.abs($0) < Self.noSignalPeak }
    }
}
