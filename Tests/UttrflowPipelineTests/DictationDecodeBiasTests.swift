// Tests that the pipeline's second decode of a piece drops the prompt and the bias by the one stated rule.
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
import UttrflowTestSupport

private let written = "Thanks for the notes. The draft is on the shared drive. I moved the review to"

/// Hears no words in its first decode and words in its second, recording the options of each.
private actor MissThenWordsSpeechEngine: SpeechEngine {
    nonisolated let kind: SpeechEngineKind = .whisperKit
    private(set) var options: [TranscriptionOptions] = []

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        self.options.append(options)
        let text = self.options.count == 1 ? "" : "what I said"
        return Transcription(text: text, audioDuration: audio.duration)
    }
}

@Suite("The bias on the pipeline's second decode")
struct DictationDecodeBiasTests {
    @Test("a piece retried after a miss is decoded without the vocabulary or the text before the caret")
    func missRetryDropsPromptAndBias() async {
        let speech = MissThenWordsSpeechEngine()
        let tone = (0..<AudioSamples.canonicalSampleRate).map { 0.3 * Float(sin(Double($0) * 0.07)) }
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.canonical(tone))),
            speech: speech,
            cleaner: FakeTranscriptCleaner(),
            context: FakeContextEngine(context: AppContext(applicationName: "Mail", precedingText: written)),
            inserter: FakeTextInserter(),
            speechWords: { _ in ["Uttrflow"] },
            clock: ManualClock())

        await pipeline.startRecording()
        await pipeline.finishRecording()

        let options = await speech.options
        #expect(options.count == 2)
        guard let first = options.first, let second = options.last else { return }
        #expect(first.vocabulary == ["Uttrflow"])
        #expect(first.precedingText != nil)
        #expect(second == DecodeBias.none.options(first))
        #expect(second.vocabulary.isEmpty && second.precedingText == nil)
    }
}
