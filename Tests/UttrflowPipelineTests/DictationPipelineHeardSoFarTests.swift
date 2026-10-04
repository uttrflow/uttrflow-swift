// Tests the finished pieces shown in the panel while the key is held, never typed into the field.
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A recogniser that names each piece by the order it was asked for.
private actor CountingSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private(set) var calls = 0

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        calls += 1
        return Transcription(
            text: "w\(calls) x", detectedLanguage: DetectedLanguage(code: .english, confidence: 1),
            audioDuration: audio.duration)
    }
}

/// A tidier that returns what it was given.
private struct EchoCleaner: TranscriptCleaning {
    func clean(_ request: TransformationRequest) async throws(TransformationError) -> TransformationResult {
        TransformationResult(text: request.transcription.text, producedBy: .foundationModels)
    }

    func warm(for situation: Situation?) async {}
}

/// Collects every value a stream gives, so a test can read the latest one.
private actor Latest {
    private(set) var values: [String?] = []
    func add(_ value: String?) { values.append(value) }
    var last: String?? { values.last }
}

@Suite("Words heard while the key is held")
struct DictationPipelineHeardSoFarTests {
    private static let rate = AudioSamples.canonicalSampleRate

    private static func tone(_ seconds: Double) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { 0.3 * Float(sin(Double($0) * 0.07)) }
    }

    private static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * Double(rate)))
    }

    /// Two phrases with a clear pause after the first, so one piece is finished while the key is held.
    private static let twoPieces = AudioSamples.canonical(
        tone(1.2) + silence(0.5) + tone(1.2) + silence(0.5) + tone(0.4))

    private static let quick = SpeechWindowing(
        minimumLength: 1, sentencePause: 0.3, comfortableLength: 2, anyPause: 0.2, maximumLength: 5,
        minimumSpeech: 0.2)

    private func start(
        secure: Bool = false, inserter: FakeTextInserter = FakeTextInserter()
    ) async -> (DictationPipeline, Latest, Task<Void, Never>, CountingSpeechEngine) {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Self.twoPieces))
        await capture.setCaptured(Self.twoPieces)
        let speech = CountingSpeechEngine()
        let pipeline = DictationPipeline(
            capture: capture, speech: speech, cleaner: EchoCleaner(),
            context: FakeContextEngine(context: .fixture(isSecure: secure)), inserter: inserter,
            windowing: Self.quick, earlyPoll: .milliseconds(2))
        let latest = Latest()
        let stream = await pipeline.wordsHeardSoFar()
        let watching = Task {
            for await words in stream { await latest.add(words) }
        }
        await pipeline.startRecording()
        return (pipeline, latest, watching, speech)
    }

    @Test("a finished piece's words are shown before key-up, and nothing is typed")
    func showsTheFirstPieceBeforeKeyUp() async throws {
        let inserter = FakeTextInserter()
        let (pipeline, latest, watching, _) = await start(inserter: inserter)
        defer { watching.cancel() }

        try await eventually { (await latest.last ?? nil)?.isEmpty == false }

        #expect(await pipeline.currentState == .recording)
        #expect(inserter.received.isEmpty)
        await pipeline.finishRecording()
        #expect(await latest.last == .some(nil))
    }

    @Test("a cancel clears the words, and nothing is typed")
    func cancelClearsTheWords() async throws {
        let inserter = FakeTextInserter()
        let (pipeline, latest, watching, _) = await start(inserter: inserter)
        defer { watching.cancel() }

        try await eventually { (await latest.last ?? nil) != nil }
        await pipeline.cancel()

        try await eventually { await latest.last == .some(nil) }
        #expect(inserter.received.isEmpty)
    }

    @Test("a secure field shows no words")
    func secureFieldShowsNothing() async throws {
        let (pipeline, latest, watching, speech) = await start(secure: true)
        defer { watching.cancel() }

        try await eventually { await speech.calls >= 2 }
        await pipeline.finishRecording()

        #expect(await latest.values.allSatisfy { $0 == nil })
    }
}
