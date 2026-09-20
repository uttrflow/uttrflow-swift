import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A recogniser that keeps the hint each piece was given and answers a different language every call.
private actor DriftingSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private let detected: [LanguageCode]
    private(set) var hints: [LanguageCode?] = []

    init(detecting detected: [LanguageCode]) {
        self.detected = detected
    }

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        hints.append(options.languageHint)
        guard hints.count <= detected.count else { throw .nothingHeard }
        return Transcription(
            text: "piece \(hints.count)",
            detectedLanguage: DetectedLanguage(code: detected[hints.count - 1], confidence: 1),
            audioDuration: audio.duration)
    }
}

private final class QuietInserter: TextInserting, Sendable {
    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        InsertionAttempt(.accessibility)
    }
}

/// A tidier that leaves the words alone, so only the hints the recogniser saw are under test.
private struct PassThroughCleaner: TranscriptCleaning {
    func clean(_ request: TransformationRequest) async throws(TransformationError) -> TransformationResult {
        TransformationResult(text: request.transcription.text, producedBy: .foundationModels)
    }

    func warm(for situation: Situation?) async {}
}

private enum Take {
    static let rate = AudioSamples.canonicalSampleRate

    static func tone(_ seconds: Double) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { 0.3 * Float(sin(Double($0) * 0.07)) }
    }

    static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * Double(rate)))
    }

    static let threePieces = AudioSamples.canonical(
        tone(1.2) + silence(0.5) + tone(1.2) + silence(0.5) + tone(1.2))
}

private let quick = SpeechWindowing(
    minimumLength: 1, sentencePause: 0.3, comfortableLength: 2, anyPause: 0.2, maximumLength: 5)

@Suite("Dictation pipeline: one language per dictation")
struct DictationPipelineLanguageTests {
    /// A pipeline over a three-piece recording and a recogniser that reports `detected`, call by call.
    private func pipeline(
        detecting detected: [LanguageCode], speaking languages: [LanguageCode] = [.english],
        earlyPoll: Duration = .milliseconds(2),
        recordings: any RecordingKeeper = RecordingsNotKept()
    ) async -> (DictationPipeline, DriftingSpeechEngine) {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let speech = DriftingSpeechEngine(detecting: detected)
        return (
            DictationPipeline(
                capture: capture, speech: speech, cleaner: PassThroughCleaner(),
                context: FakeContextEngine(context: .fixture()), inserter: QuietInserter(),
                recordings: recordings, profile: UserProfile(preferredLanguages: languages),
                windowing: quick, earlyPoll: earlyPoll),
            speech
        )
    }

    /// The defect: a quiet or name-heavy later piece detecting another language decodes half an utterance in it.
    @Test("hints every piece after the first with the language the first piece was heard in")
    func carriesTheFirstDetection() async {
        let (pipeline, speech) = await pipeline(detecting: [.english, .hindi, .hindi])

        await pipeline.startRecording()
        await pipeline.finishRecording()
        let hints = await speech.hints

        #expect(hints.count > 1)
        #expect(hints.first == .some(nil))
        #expect(hints.dropFirst().allSatisfy { $0 == .english })
    }

    /// The next dictation may be spoken in another language, so the answer is per dictation and not for ever.
    @Test("detects again for the next dictation rather than keeping the last one's language")
    func forgetsBetweenDictations() async {
        let (pipeline, speech) = await pipeline(
            detecting: [.english, .english, .english, .hindi, .hindi, .hindi])

        await pipeline.startRecording()
        await pipeline.finishRecording()
        let first = await speech.hints.count
        await pipeline.startRecording()
        await pipeline.finishRecording()
        let hints = await speech.hints

        #expect(hints.count > first)
        #expect(hints[first] == nil)
        #expect(hints[(first + 1)...].allSatisfy { $0 == .hindi })
    }

    /// A retry is its own attempt, so it detects its own language rather than the last dictation's.
    @Test("detects again for a retry rather than keeping the last dictation's language")
    func forgetsBeforeARetry() async {
        let kept = KeptRecording(id: UUID(), when: Date(), duration: .seconds(4))
        let (pipeline, speech) = await pipeline(
            detecting: [.english, .english, .english, .hindi, .hindi, .hindi],
            recordings: FakeRecordingKeeper(waiting: [kept], audioOutcome: .success(Take.threePieces)))

        await pipeline.startRecording()
        await pipeline.finishRecording()
        let first = await speech.hints.count
        await pipeline.retry(kept.id)
        let hints = await speech.hints

        #expect(hints.count > first)
        #expect(hints[first] == nil)
    }

    /// Issue 698: a Hinglish speaker's Hindi sentence after an English one was decoded as English and translated.
    @Test(
        "detects every piece for a speaker of English and Hindi, rather than holding the first piece's English"
    )
    func detectsEachPieceForBothLanguages() async {
        let (pipeline, speech) = await pipeline(
            detecting: [.english, .hindi, .hindi], speaking: [.english, .hindi])

        await pipeline.startRecording()
        await pipeline.finishRecording()
        let hints = await speech.hints

        #expect(hints.count > 1)
        #expect(hints.allSatisfy { $0 == nil })
    }

    /// Issue 699: a short Hindi reply was detected as English words.
    @Test("decodes every piece as Hindi for a speaker of Hindi alone")
    func pinsHindiAlone() async {
        let (pipeline, speech) = await pipeline(
            detecting: [.english, .english, .english], speaking: [.hindi])

        await pipeline.startRecording()
        await pipeline.finishRecording()
        let hints = await speech.hints

        #expect(hints.count > 1)
        #expect(hints.allSatisfy { $0 == .hindi })
    }

    @Test("listens by the languages adopted since it was built, from the next dictation on")
    func adoptsTheProfile() async {
        let (pipeline, speech) = await pipeline(detecting: [.english, .hindi, .hindi, .hindi, .hindi, .hindi])

        await pipeline.adopt(profile: UserProfile(preferredLanguages: [.hindi]))
        await pipeline.startRecording()
        await pipeline.finishRecording()
        let hints = await speech.hints

        #expect(!hints.isEmpty)
        #expect(hints.allSatisfy { $0 == .hindi })
    }

    /// Issue 786: a change made while speaking re-hinted the pieces still to come under the new languages.
    @Test("keeps a recording on the languages it began with, and adopts a change from the next")
    func profileChangedMidRecordingWaits() async {
        // No early pieces, so every piece is recognised after the change and none could escape it.
        let (pipeline, speech) = await pipeline(
            detecting: [.english, .english, .english, .english, .english, .english],
            earlyPoll: .seconds(60))

        await pipeline.startRecording()
        await pipeline.adopt(profile: UserProfile(preferredLanguages: [.hindi]))
        await pipeline.finishRecording()
        let first = await speech.hints

        #expect(first.count > 1, "a recording of several pieces")
        #expect(first.first == .some(nil), "the English profile detects the first piece")
        #expect(first.dropFirst().allSatisfy { $0 == .english }, "then carries it, not Hindi")

        await pipeline.startRecording()
        await pipeline.finishRecording()
        let next = await speech.hints.dropFirst(first.count)

        #expect(!next.isEmpty)
        #expect(next.allSatisfy { $0 == .hindi }, "the next dictation listens by the new languages")
    }
}
