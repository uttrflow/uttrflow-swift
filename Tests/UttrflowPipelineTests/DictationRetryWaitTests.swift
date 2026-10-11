// Tests that a piece decoded a second time names that second decode as the dictation's slow cause.
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
import UttrflowTestSupport

/// A recogniser that hears no words in its first decode and words in its second, each costing its scripted time.
private actor SecondDecodeSpeechEngine: SpeechEngine {
    nonisolated let kind: SpeechEngineKind = .whisperKit
    private let clock: ManualClock
    private let first: Duration
    private let second: Duration
    private var calls = 0

    init(clock: ManualClock, first: Duration, second: Duration) {
        self.clock = clock
        self.first = first
        self.second = second
    }

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        calls += 1
        if calls == 1 {
            clock.advance(by: first)
            return Transcription(text: "", audioDuration: audio.duration)
        }
        clock.advance(by: second)
        return Transcription(
            text: "what I said", audioDuration: audio.duration,
            effort: DecodeEffort(fallbacks: 1, fallbackSeconds: 1))
    }
}

@Suite("Naming a second decode in the wait")
struct DictationRetryWaitTests {
    @Test("a speech-bearing piece decoded again names the second decode, less its fallbacks, as the retry")
    func secondDecodeIsTheRetry() async {
        let clock = ManualClock()
        let metrics = RecordingMetricsRecorder()
        let tone = (0..<AudioSamples.canonicalSampleRate).map { 0.3 * Float(sin(Double($0) * 0.07)) }
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.canonical(tone))),
            speech: SecondDecodeSpeechEngine(clock: clock, first: .seconds(1), second: .seconds(6)),
            cleaner: FakeTranscriptCleaner(),
            context: FakeContextEngine(),
            inserter: FakeTextInserter(),
            metrics: metrics,
            clock: clock)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await metrics.decoding.map(\.retrySeconds) == [5])
        #expect(await metrics.waits.map(\.cause) == [.cappedDecodeRetry])
        #expect(await metrics.waits.first?.wait.spent[.cappedDecodeRetry] == .seconds(5))
    }
}
