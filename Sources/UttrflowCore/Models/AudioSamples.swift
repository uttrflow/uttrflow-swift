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

    /// Creates a buffer, rejecting a non-positive sample rate.
    public init?(samples: [Float], sampleRate: Int) {
        guard sampleRate > 0 else { return nil }
        self.init(unchecked: samples, sampleRate: sampleRate)
    }

    /// Stores a rate already known to be positive.
    private init(unchecked samples: [Float], sampleRate: Int) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    /// Wraps samples already at ``canonicalSampleRate``, without a `nil` branch that cannot happen.
    public static func canonical(_ samples: [Float]) -> AudioSamples {
        AudioSamples(unchecked: samples, sampleRate: canonicalSampleRate)
    }

    public var isEmpty: Bool { samples.isEmpty }

    /// Wall-clock length of the recording.
    public var duration: Duration {
        .seconds(Double(samples.count) / Double(sampleRate))
    }
}
