import Testing

@testable import UttrflowCore
@testable import UttrflowTestSupport

private struct StubError: Error {}

@Suite("Stage measurement")
struct MetricsTests {
    @Test("records how long a successful stage took")
    func recordsSuccessDuration() async {
        let recorder = RecordingMetricsRecorder()
        let clock = ManualClock()

        let value = await recorder.measuring(.transcription, clock: clock) {
            clock.advance(by: .milliseconds(1_500))
            return "text"
        }

        let measurements = await recorder.measurements
        #expect(value == "text")
        #expect(
            measurements == [.init(stage: .transcription, duration: .milliseconds(1_500), succeeded: true)])
    }

    @Test("records a failing stage and rethrows the original error")
    func recordsFailureAndRethrows() async {
        let recorder = RecordingMetricsRecorder()
        let clock = ManualClock()

        await #expect(throws: StubError.self) {
            try await recorder.measuring(.insertion, clock: clock) { () throws(StubError) -> Void in
                clock.advance(by: .milliseconds(20))
                throw StubError()
            }
        }

        let measurements = await recorder.measurements
        #expect(measurements.count == 1)
        #expect(measurements.first?.stage == .insertion)
        #expect(measurements.first?.succeeded == false)
        #expect(measurements.first?.duration == .milliseconds(20))
    }

    @Test("measures each stage separately so a regression can be attributed")
    func measuresEveryStageIndependently() async {
        let recorder = RecordingMetricsRecorder()
        let clock = ManualClock()

        for (index, stage) in PipelineStage.allCases.enumerated() {
            await recorder.measuring(stage, clock: clock) {
                clock.advance(by: .milliseconds(index + 1))
            }
        }

        for (index, stage) in PipelineStage.allCases.enumerated() {
            let recorded = await recorder.measurements(for: stage)
            #expect(recorded.map(\.duration) == [.milliseconds(index + 1)])
        }
    }

    @Test("records a zero duration when a stage takes no measurable time")
    func zeroDuration() async {
        let recorder = RecordingMetricsRecorder()
        await recorder.measuring(.capture, clock: ManualClock()) {}

        let measurements = await recorder.measurements
        #expect(measurements.first?.duration == .zero)
    }

    @Test("discards everything when the caller does not want measurements")
    func noOpRecorder() async {
        let recorder = NoOpMetricsRecorder()
        let value = await recorder.measuring(.capture, clock: ManualClock()) { 42 }
        #expect(value == 42)
    }
}

@Suite("ManualClock")
struct ManualClockTests {
    @Test("starts at zero and only moves when advanced")
    func advancesOnlyOnDemand() {
        let clock = ManualClock()
        let start = clock.now

        #expect(start.duration(to: clock.now) == .zero)
        clock.advance(by: .seconds(3))
        #expect(start.duration(to: clock.now) == .seconds(3))
    }

    @Test("jumps straight to a deadline instead of waiting")
    func sleepIsInstant() async throws {
        let clock = ManualClock()
        try await clock.sleep(until: clock.now.advanced(by: .seconds(10)), tolerance: nil)
        #expect(ManualClock.Instant(offset: .zero).duration(to: clock.now) == .seconds(10))
    }

    @Test("never moves backwards when asked to sleep until a past deadline")
    func sleepDoesNotRewind() async throws {
        let clock = ManualClock()
        clock.advance(by: .seconds(5))
        try await clock.sleep(until: ManualClock.Instant(offset: .seconds(1)), tolerance: nil)
        #expect(ManualClock.Instant(offset: .zero).duration(to: clock.now) == .seconds(5))
    }

    @Test("orders instants by their offset")
    func instantsAreComparable() {
        #expect(ManualClock.Instant(offset: .seconds(1)) < ManualClock.Instant(offset: .seconds(2)))
        #expect(ManualClock().minimumResolution == .nanoseconds(1))
    }
}
