// Tests that a tidier session started cold is named as the dictation's slow cause.
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
import UttrflowTestSupport

/// A cleaner that reports a cold start of its scripted length to whoever is listening, and takes that long.
private final class ColdSessionCleaner: TranscriptCleaning, Sendable {
    private let clock: ManualClock
    private let cold: Duration

    init(clock: ManualClock, cold: Duration) {
        self.clock = clock
        self.cold = cold
    }

    func clean(_ request: TransformationRequest) async throws(TransformationError) -> TransformationResult {
        clock.advance(by: cold)
        ColdStartMeter.current?.add(cold)
        return TransformationResult(text: request.transcription.text, producedBy: .rules)
    }

    func finishMessage(_ text: String, for request: TransformationRequest) async -> String { text }

    func reserveFinalPiece(_ situation: Situation?) async {}
}

@Suite("Naming a cold tidier session in the wait")
struct DictationColdTidyWaitTests {
    @Test("a tidier that starts cold reports its time to the dictation's wait, which names it")
    func coldStartIsNamed() async {
        let clock = ManualClock()
        let metrics = RecordingMetricsRecorder()
        let tone = (0..<AudioSamples.canonicalSampleRate).map { 0.3 * Float(sin(Double($0) * 0.07)) }
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.canonical(tone))),
            speech: FakeSpeechEngine(),
            cleaner: ColdSessionCleaner(clock: clock, cold: .seconds(6)),
            context: FakeContextEngine(),
            inserter: FakeTextInserter(),
            metrics: metrics,
            clock: clock)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await metrics.tidyColdStarts == [.seconds(6)])
        #expect(await metrics.waits.first?.wait.spent[.tidyColdSession] == .seconds(6))
        #expect(await metrics.waits.map(\.cause) == [.tidyColdSession])
    }
}
