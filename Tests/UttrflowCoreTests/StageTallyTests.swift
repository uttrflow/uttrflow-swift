// Tests for StageTally.

import Testing

@testable import UttrflowCore

@Suite("StageTally")
struct StageTallyTests {
    @Test("adds up every measurement of a stage into one")
    func sumsDurations() async {
        let tally = StageTally()
        await tally.record(StageMeasurement(stage: .transcription, duration: .seconds(1), succeeded: true))
        await tally.record(StageMeasurement(stage: .transcription, duration: .seconds(2), succeeded: true))
        await tally.record(StageMeasurement(stage: .transformation, duration: .seconds(4), succeeded: true))

        let expected = [
            StageMeasurement(stage: .transcription, duration: .seconds(3), succeeded: true),
            StageMeasurement(stage: .transformation, duration: .seconds(4), succeeded: true),
        ]
        #expect(await tally.measurements == expected)
    }

    @Test("keeps the dictation generation when reporting totals")
    func reportsGeneration() async {
        let tally = StageTally()
        let recorder = RecordingRecorder()
        await tally.record(
            StageMeasurement(stage: .transcription, duration: .seconds(1), succeeded: true, generation: 12))
        await tally.record(
            StageMeasurement(stage: .transcription, duration: .seconds(2), succeeded: true, generation: 12))

        await tally.report(to: recorder)

        #expect(await recorder.measurements.first?.duration == .seconds(3))
        #expect(await recorder.measurements.first?.generation == 12)
    }

    @Test("one failure makes the stage's total a failure")
    func failureSticks() async {
        let tally = StageTally()
        await tally.record(StageMeasurement(stage: .correction, duration: .seconds(1), succeeded: true))
        await tally.record(StageMeasurement(stage: .correction, duration: .seconds(1), succeeded: false))
        await tally.record(StageMeasurement(stage: .correction, duration: .seconds(1), succeeded: true))

        #expect(await tally.measurements.first?.succeeded == false)
    }

    @Test("reports one measurement per stage, in the order the journey runs")
    func reportsInStageOrder() async {
        let tally = StageTally()
        let recorder = RecordingRecorder()
        await tally.record(StageMeasurement(stage: .insertion, duration: .seconds(1), succeeded: true))
        await tally.record(StageMeasurement(stage: .capture, duration: .seconds(1), succeeded: true))

        await tally.report(to: recorder)

        #expect(await recorder.stages == [.capture, .insertion])
    }

    @Test("reports nothing when nothing was measured")
    func reportsNothingWhenEmpty() async {
        let recorder = RecordingRecorder()
        await StageTally().report(to: recorder)
        #expect(await recorder.stages.isEmpty)
    }
}

private actor RecordingRecorder: MetricsRecording {
    private(set) var measurements: [StageMeasurement] = []
    var stages: [PipelineStage] { measurements.map(\.stage) }
    func record(_ measurement: StageMeasurement) { measurements.append(measurement) }
}
