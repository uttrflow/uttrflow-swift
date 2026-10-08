import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A recogniser that keeps each hint and reports the detected language of its first piece.
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

/// A recogniser that holds its first call until released, then answers `.hindi`; later calls answer `.english`.
private actor HeldSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private(set) var hints: [LanguageCode?] = []
    private(set) var firstReturned = false
    private var held: CheckedContinuation<Void, Never>?
    private var released = false

    func prepare() async throws(SpeechEngineError) {}

    func release() {
        released = true
        held?.resume()
        held = nil
    }

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        hints.append(options.languageHint)
        let first = hints.count == 1
        if first, !released { await withCheckedContinuation { held = $0 } }
        if first { firstReturned = true }
        return Transcription(
            text: "piece \(hints.count)",
            detectedLanguage: DetectedLanguage(code: first ? .hindi : .english, confidence: 1),
            audioDuration: audio.duration)
    }
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
    minimumLength: 1, sentencePause: 0.3, comfortableLength: 2, anyPause: 0.2, maximumLength: 5,
    minimumSpeech: 0.2)

@Suite("Dictation pipeline: one language per dictation")
struct DictationPipelineLanguageTests {
    /// A pipeline over a three-piece recording and a recogniser that reports `detected`, call by call.
    private func pipeline(
        detecting detected: [LanguageCode], profile: UserProfile = .default,
        earlyPoll: Duration = .milliseconds(2),
        recordings: any RecordingKeeper = RecordingsNotKept()
    ) async -> (DictationPipeline, DriftingSpeechEngine) {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let speech = DriftingSpeechEngine(detecting: detected)
        return (
            DictationPipeline(
                capture: capture, speech: speech,
                cleaner: FakeTranscriptCleaner(producedBy: .foundationModels),
                context: FakeContextEngine(context: .fixture()), inserter: FakeTextInserter(),
                recordings: recordings, profile: profile,
                windowing: quick, earlyPoll: earlyPoll),
            speech
        )
    }

    /// A default profile detects each pause-delimited piece without a language hint.
    @Test("detects each piece independently for the default profile")
    func detectsEveryPieceForDefaultProfile() async {
        let (pipeline, speech) = await pipeline(detecting: [.english, .hindi, .hindi])

        await pipeline.startRecording()
        await pipeline.finishRecording()
        let hints = await speech.hints

        #expect(hints.count > 1)
        #expect(hints.allSatisfy { $0 == nil })
    }

    /// Each dictation resolves its own language settings and detects every piece again.
    @Test("detects every piece again for the next dictation")
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
        #expect(hints.dropFirst(first).allSatisfy { $0 == nil })
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

    /// A bilingual profile can change languages between pause-delimited pieces.
    @Test("detects a Hindi-to-English switch for a bilingual profile")
    func detectsEachPieceForBothLanguages() async {
        let (pipeline, speech) = await pipeline(
            detecting: [.hindi, .english, .english],
            profile: UserProfile(preferredLanguages: [.english, .hindi]))

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
            detecting: [.english, .english, .english], profile: UserProfile(preferredLanguages: [.hindi]))

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
        #expect(first.dropFirst().allSatisfy { $0 == nil }, "the original profile detects every piece")

        await pipeline.startRecording()
        await pipeline.finishRecording()
        let next = await speech.hints.dropFirst(first.count)

        #expect(!next.isEmpty)
        #expect(next.allSatisfy { $0 == .hindi }, "the next dictation listens by the new languages")
    }

    /// Issue 1519: a cancelled piece still in the recogniser set the next dictation's language when it returned.
    @Test("a cancelled dictation's piece in flight does not set the next dictation's language")
    func cancelledPieceDoesNotHintTheNext() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let speech = HeldSpeechEngine()
        let pipeline = DictationPipeline(
            capture: capture, speech: speech, cleaner: FakeTranscriptCleaner(producedBy: .foundationModels),
            context: FakeContextEngine(context: .fixture()), inserter: FakeTextInserter(),
            recordings: RecordingsNotKept(), profile: UserProfile(preferredLanguages: [.english]),
            windowing: quick, earlyPoll: .milliseconds(2))

        await pipeline.startRecording()
        try await eventually { await speech.hints.count == 1 }
        await pipeline.cancel()
        // A start is refused while the abandoned decode is still in the recogniser, so the next one waits for it.
        await speech.release()
        try await eventually { await speech.firstReturned }
        for _ in 0..<50 { await Task.yield() }
        await pipeline.startRecording()
        await pipeline.finishRecording()
        let later = await speech.hints.dropFirst(2)

        #expect(!later.isEmpty)
        #expect(later.allSatisfy { $0 != .hindi }, "the abandoned piece's language is not hinted")
    }
}
