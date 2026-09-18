import Foundation
import Synchronization
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A recogniser that hears the same words in every piece.
private actor HearingSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private let heard: String

    init(hearing heard: String) {
        self.heard = heard
    }

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        Transcription(
            text: heard, detectedLanguage: DetectedLanguage(code: .hindi, confidence: 1),
            audioDuration: audio.duration)
    }
}

/// An inserter that keeps what it was handed.
private final class KeepingInserter: TextInserting, Sendable {
    private let kept = Mutex<[String]>([])

    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        kept.withLock { $0.append(text) }
        return InsertionAttempt(.accessibility)
    }

    var texts: [String] { kept.withLock { $0 } }
}

/// A tidier that hands back the words as heard, in whatever script they came.
private struct EchoingCleaner: TranscriptCleaning {
    func clean(_ request: TransformationRequest) async throws(TransformationError) -> TransformationResult {
        TransformationResult(text: request.transcription.text, producedBy: .foundationModels)
    }

    func warm(for situation: Situation?) async {}
}

/// A tidier that always fails, so the words go in untidied.
private struct FailingCleaner: TranscriptCleaning {
    func clean(_ request: TransformationRequest) async throws(TransformationError) -> TransformationResult {
        throw .noCapableTransformer
    }

    func warm(for situation: Situation?) async {}
}

@Suite("Dictation pipeline: Latin letters only")
struct DictationPipelineLatinOutputTests {
    /// One short take, heard as `heard`, tidied by `cleaner`, and what was inserted.
    private func dictate(_ heard: String, cleaner: any TranscriptCleaning) async -> [String] {
        let rate = AudioSamples.canonicalSampleRate
        let take = AudioSamples.canonical(
            (0..<Int(1.2 * Double(rate))).map { 0.3 * Float(sin(Double($0) * 0.07)) })
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(take))
        await capture.setCaptured(take)
        let inserter = KeepingInserter()
        let pipeline = DictationPipeline(
            capture: capture, speech: HearingSpeechEngine(hearing: heard), cleaner: cleaner,
            context: FakeContextEngine(context: .fixture()), inserter: inserter)
        await pipeline.startRecording()
        await pipeline.finishRecording()
        return inserter.texts
    }

    @Test("romanises Devanagari that no tidier romanised, whether the tidy failed or handed the words back")
    func romanisesUntidiedDevanagari() async {
        for cleaner: any TranscriptCleaning in [FailingCleaner(), EchoingCleaner()] {
            let inserted = await dictate("हाँ ठीक है।", cleaner: cleaner)
            #expect(inserted.count == 1)
            #expect(inserted.allSatisfy { !Romaniser.containsDevanagari($0) && LatinScript.isLatin($0) })
            #expect(inserted.first?.hasPrefix("Haan thik hai") == true, "\(inserted)")
        }
    }

    @Test("inserts romanised Hinglish on the shipping floor when the model is not there")
    func rulesFloorRomanises() async {
        let router = TransformerRouter(
            engines: [RuleBasedTransformer()], preference: [.foundationModels, .rules],
            rulesAlone: .shortReplies)
        let inserted = await dictate("मैं अभी आता हूँ", cleaner: router)
        #expect(inserted.count == 1)
        #expect(inserted.first?.hasPrefix("Main abhi aata hoon") == true, "\(inserted)")
    }

    @Test("writes another script in Latin letters rather than insert it")
    func transliteratesOtherScripts() async {
        let inserted = await dictate("Привет", cleaner: EchoingCleaner())
        #expect(inserted.count == 1)
        #expect(inserted.allSatisfy { LatinScript.isLatin($0) })
    }

    @Test(
        "inserts English exactly as the tidier wrote it",
        arguments: ["Okay, see you at 5 p.m. 👍", "Café “naïve” — résumé…", "x² ≤ ½, ₹1,50,000 and 3.5%"])
    func leavesEnglishAlone(text: String) async {
        #expect(await dictate(text, cleaner: EchoingCleaner()) == [text])
    }
}
