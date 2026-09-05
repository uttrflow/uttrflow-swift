// The typical and worst of a set of timings.
public import UttrflowCore

/// The typical and worst of a set of timings for something that is not a ``PipelineStage``.
public struct DurationSummary: Sendable, Equatable {
    /// The median, on the same convention as ``StageLatency/typical``.
    public let typical: Duration
    public let slowest: Duration
    public let samples: Int
    /// How many of those samples were failures. A journey can be fast because it gave up.
    public let failures: Int

    public init(typical: Duration, slowest: Duration, samples: Int, failures: Int) {
        self.typical = typical
        self.slowest = slowest
        self.samples = samples
        self.failures = failures
    }

    public init(_ latency: StageLatency) {
        self.init(
            typical: latency.typical, slowest: latency.slowest, samples: latency.samples,
            failures: latency.failures)
    }

    /// Summarises durations through the project's one median, or `nil` when there are none.
    public static func over(_ durations: [Duration], failures: Int = 0) -> DurationSummary? {
        let carried = durations.map {
            StageMeasurement(stage: .transcription, duration: $0, succeeded: true)
        }
        guard let latency = StageLatency.summarise(carried, stage: .transcription) else {
            return nil
        }
        return DurationSummary(
            typical: latency.typical, slowest: latency.slowest, samples: latency.samples,
            failures: failures)
    }
}
