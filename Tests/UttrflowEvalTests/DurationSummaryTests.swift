// Tests the end-to-end duration summary.
import UttrflowCore
import Testing

@testable import UttrflowEval

@Suite("Summarising plain durations")
struct DurationSummaryTests {
    @Test("nothing measured summarises to nothing, not to zero")
    func emptyIsNil() {
        #expect(DurationSummary.over([]) == nil)
    }

    @Test("the typical and the slowest come off the same set")
    func typicalAndSlowest() {
        let summary = DurationSummary.over([.seconds(3), .seconds(1), .seconds(2)])
        #expect(summary?.typical == .seconds(2))
        #expect(summary?.slowest == .seconds(3))
        #expect(summary?.samples == 3)
        #expect(summary?.failures == 0)
    }

    /// ``StageLatency`` takes the upper of two middle samples, and the end-to-end row must agree with it.
    @Test("an even number of samples ties the same way StageLatency does")
    func tieBreaksLikeStageLatency() {
        let durations: [Duration] = [.seconds(1), .seconds(2)]
        let measurements = durations.map {
            StageMeasurement(stage: .transcription, duration: $0, succeeded: true)
        }
        let viaStage = StageLatency.summarise(measurements, stage: .transcription)
        #expect(DurationSummary.over(durations)?.typical == viaStage?.typical)
        #expect(DurationSummary.over(durations)?.typical == .seconds(2))
    }

    /// A journey can be fast because it gave up, so the failure count travels with the timings.
    @Test("failures are carried, not inferred")
    func failuresAreCarried() {
        #expect(DurationSummary.over([.seconds(1)], failures: 1)?.failures == 1)
    }

    @Test("a stage latency converts without changing any figure")
    func convertsFromStageLatency() {
        let latency = StageLatency(
            stage: .transformation, typical: .seconds(2), slowest: .seconds(9), samples: 4,
            failures: 1)
        let summary = DurationSummary(latency)
        #expect(summary.typical == .seconds(2))
        #expect(summary.slowest == .seconds(9))
        #expect(summary.samples == 4)
        #expect(summary.failures == 1)
    }
}
