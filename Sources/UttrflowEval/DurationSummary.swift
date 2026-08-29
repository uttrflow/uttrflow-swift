public import UttrflowCore

/// The typical and the worst of a set of timings, for something that is not a
/// ``PipelineStage``.
///
/// ``StageLatency`` already answers "what is this usually like" for one stage, and the
/// end-to-end journey needs the same answer without being a stage. The median is not
/// reimplemented here — see ``over(_:failures:)`` — because two medians with two
/// tie-breaking rules eventually describe the same machine differently, and the
/// disagreement always surfaces as an argument about the machine rather than the code.
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

    /// Summarises plain durations, or `nil` when there are none.
    ///
    /// The durations are handed to ``StageLatency/summarise(_:stage:)`` under a stage
    /// label that is then thrown away. That looks roundabout and is the point: it is the
    /// only median in the project, so the end-to-end row and the per-stage rows below it
    /// cannot round or tie-break differently.
    /// - Parameters:
    ///   - durations: Every timing, in any order.
    ///   - failures: How many of them were failures. Carried separately because the
    ///     caller knows which journeys ended badly and a bare duration does not.
    /// - Returns: The summary, or `nil` when there were no durations at all — which is
    ///   not the same as a summary of zero.
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
