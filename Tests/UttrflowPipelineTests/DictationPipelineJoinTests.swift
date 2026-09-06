import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// A recogniser that reads out a scripted line per call, so a dictation's pieces are known in advance.
private actor ScriptedSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private let lines: [String]
    private(set) var calls = 0

    init(_ lines: [String]) {
        self.lines = lines
    }

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        calls += 1
        guard calls <= lines.count else { throw .nothingHeard }
        return Transcription(
            text: lines[calls - 1], detectedLanguage: DetectedLanguage(code: .english, confidence: 1),
            audioDuration: audio.duration)
    }
}

/// A tidier that finishes each piece the way the real one does — a capital at the front, a full stop at the end.
private struct FinishingCleaner: TranscriptCleaning {
    func clean(_ request: TransformationRequest) async throws(TransformationError) -> TransformationResult {
        let finished = WordShape.finished(WordShape.capitalised(request.transcription.text))
        return TransformationResult(text: finished, producedBy: .foundationModels)
    }

    func warm(for situation: Situation?) async {}
}

private final class CollectingInserter: TextInserting, Sendable {
    private let received = Mutex<[String]>([])

    func insert(_ text: String) async throws(TextInsertionError) -> TextInsertionMethod {
        received.withLock { $0.append(text) }
        return .accessibility
    }

    var texts: [String] { received.withLock { $0 } }
}

/// A recording with a clear pause between each of its three phrases.
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

/// Windows short enough for a test recording to have several.
private let quick = SpeechWindowing(
    minimumLength: 1, sentencePause: 0.3, comfortableLength: 2, anyPause: 0.2, maximumLength: 5)

extension DictationState {
    fileprivate var inserted: String? {
        if case .inserted(let outcome) = self { outcome.text } else { nil }
    }
}

// MARK: - Tests

@Suite("Dictation pipeline: laying out the pieces it joins")
struct DictationPipelineJoinTests {
    /// Runs one whole dictation of three pieces against the screen `context` shows, answering what was inserted.
    private func dictate(_ lines: [String], seeing context: AppContext) async -> String? {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let inserter = CollectingInserter()
        let pipeline = DictationPipeline(
            capture: capture, speech: ScriptedSpeechEngine(lines), cleaner: FinishingCleaner(),
            context: FakeContextEngine(context: context), inserter: inserter, windowing: quick,
            earlyPoll: .milliseconds(2))

        await pipeline.startRecording()
        await pipeline.finishRecording()
        return await pipeline.currentState.inserted
    }

    private static let document = AppContext.fixture(
        applicationName: "TextEdit", bundleIdentifier: "com.apple.TextEdit", documentName: "Notes")
    private static let sheet = AppContext.fixture(
        applicationName: "Numbers", bundleIdentifier: "com.apple.iWork.Numbers", documentName: "Sheet 1")
    private static let mail = AppContext.fixture(
        applicationName: "Mail", bundleIdentifier: "com.apple.mail", documentName: "Draft")

    @Test("a spoken sequence over three pieces of a real dictation becomes a list in a document")
    func listInADocument() async {
        let text = await dictate(
            ["first we fix the build", "second we review the PR", "third we ship it"],
            seeing: Self.document)
        #expect(text == "- We fix the build\n- We review the PR\n- We ship it")
    }

    @Test("the same dictation into a chat window stays prose")
    func listInAChatStaysProse() async {
        let text = await dictate(
            ["first we fix the build", "second we review the PR", "third we ship it"],
            seeing: .fixture())
        #expect(text == "First we fix the build.\n\nSecond we review the PR.\n\nThird we ship it.")
    }

    @Test("a topic word after a pause opens a paragraph in an email")
    func topicWordInAnEmail() async {
        let text = await dictate(
            ["thanks for the update", "also the deck is ready", "the build is green"], seeing: Self.mail)
        #expect(text == "Thanks for the update.\n\nAlso the deck is ready. The build is green.")
    }

    @Test("a cell never gets a line break, whatever the speaker opened a piece with")
    func spreadsheetStaysOnOneLine() async {
        let text = await dictate(
            ["first we fix the build", "second we review the PR", "also the deck is ready"],
            seeing: Self.sheet)
        #expect(
            text == "First we fix the build. Second we review the PR. Also the deck is ready.")
    }

    @Test("a correction the speaker made across a pause takes the words it replaced with it")
    func restatementAcrossAPause() async {
        let text = await dictate(
            ["let's meet at four", "no sorry at five", "in the small room"], seeing: Self.document)
        #expect(text == "Let's meet at five. In the small room.")
    }
}
