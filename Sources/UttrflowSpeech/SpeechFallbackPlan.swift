// How the recogniser retries a window its own thresholds reject, named so a sweep can vary it.

/// The temperature retries and log-probability test a decode uses; only a measurement harness passes another plan.
public struct SpeechFallbackPlan: Sendable, Equatable {
    /// How many warmer re-decodes a rejected window may have.
    public let temperatureCount: Int
    /// The mean token log-probability under which a window counts as rejected.
    public let logProbThreshold: Float

    public init(temperatureCount: Int, logProbThreshold: Float) {
        self.temperatureCount = temperatureCount
        self.logProbThreshold = logProbThreshold
    }

    /// Whisper's own values, which the product ships; see `Docs/speech-engines.md` for the sweep against them.
    public static let shipping = SpeechFallbackPlan(temperatureCount: 5, logProbThreshold: -1.0)
}
