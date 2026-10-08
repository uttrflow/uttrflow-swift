// Tests generation tags on measurements recorded by the dictation pipeline.

import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("Pipeline measurement generations")
struct PipelineMeasurementGenerationTests {
    @Test("reserves the generation before measuring the early microphone opening")
    func earlyMicrophoneOpeningUsesReservedGeneration() async {
        let metrics = RecordingMetricsRecorder()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(),
            cleaner: FakeTranscriptCleaner(), context: FakeContextEngine(context: .fixture()),
            inserter: FakeTextInserter(), metrics: metrics, clock: ManualClock())

        await pipeline.beginModifierPress(measuring: { .zero })

        let measurement = await metrics.measurements.first
        #expect(measurement?.stage == .microphoneOpen)
        #expect(measurement?.generation == 1)
        let snapshot = pipeline.currentStateSnapshot
        #expect(snapshot.generation == 1)
        await pipeline.cancelModifierPress()
    }
}
