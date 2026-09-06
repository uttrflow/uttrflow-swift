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
    var stages: [PipelineStage] = []
    func record(_ measurement: StageMeasurement) { stages.append(measurement.stage) }
}
