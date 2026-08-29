/// A block of mono PCM audio, normalised to `-1...1`.
///
/// Every engine in the pipeline speaks this one format, so format conversion happens
/// exactly once — at the capture boundary — instead of at each consumer.
public struct AudioSamples: Sendable, Equatable {
    /// The sample rate every speech engine in the product expects.
    public static let canonicalSampleRate = 16_000

    /// An empty buffer at the canonical rate. Useful as a neutral value in tests and
    /// as the result of a cancelled recording.
    public static let empty = AudioSamples(unchecked: [], sampleRate: canonicalSampleRate)

    public let samples: [Float]
    public let sampleRate: Int

    /// Creates a buffer, rejecting a non-positive sample rate.
    public init?(samples: [Float], sampleRate: Int) {
        guard sampleRate > 0 else { return nil }
        self.init(unchecked: samples, sampleRate: sampleRate)
    }

    private init(unchecked samples: [Float], sampleRate: Int) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    /// Wraps samples already at ``canonicalSampleRate``.
    ///
    /// Non-failing, because the rate is a compile-time constant — callers of the
    /// failable initialiser would otherwise carry a `nil` branch that cannot happen.
    public static func canonical(_ samples: [Float]) -> AudioSamples {
        AudioSamples(unchecked: samples, sampleRate: canonicalSampleRate)
    }

    public var isEmpty: Bool { samples.isEmpty }

    /// Wall-clock length of the recording.
    public var duration: Duration {
        .seconds(Double(samples.count) / Double(sampleRate))
    }
}
