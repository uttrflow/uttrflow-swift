import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// A recogniser that reads out a scripted line per call and hears nothing once they run out.
private func reading(_ lines: [String]) -> FakeSpeechEngine {
    let heard = lines.map {
        Transcription(text: $0, detectedLanguage: DetectedLanguage(code: .english, confidence: 1))
    }
    return FakeSpeechEngine(transcribing: .successes(heard, afterwards: .failure(.nothingHeard)))
}

/// A tidier that finishes each piece the way the real one does — a capital at the front, a full stop at the end.
private func finishing() -> FakeTranscriptCleaner {
    FakeTranscriptCleaner(
        tidying: { WordShape.finished(WordShape.capitalised($0)) }, producedBy: .foundationModels)
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
    minimumLength: 1, sentencePause: 0.3, comfortableLength: 2, anyPause: 0.2, maximumLength: 5,
    minimumSpeech: 0.2)

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
        let inserter = FakeTextInserter()
        let pipeline = DictationPipeline(
            capture: capture, speech: reading(lines), cleaner: finishing(),
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

    @Test("every piece after the first is tidied knowing the previous piece as heard")
    func tidierSeesThePreviousPiece() async {
        let lines = ["we waited for the build", "because the runner was slow", "and then it passed"]
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let cleaner = finishing()
        let pipeline = DictationPipeline(
            capture: capture, speech: reading(lines), cleaner: cleaner,
            context: FakeContextEngine(context: Self.document), inserter: FakeTextInserter(),
            windowing: quick, earlyPoll: .milliseconds(2))

        await pipeline.startRecording()
        await pipeline.finishRecording()

        let seen = Dictionary(
            cleaner.requests.filter { $0.scope == .piece }.map { ($0.transcription.text, $0.precedingPiece) },
            uniquingKeysWith: { first, _ in first })
        let expected: [String: String?] = [lines[0]: nil, lines[1]: lines[0], lines[2]: lines[1]]
        #expect(seen == expected)
    }

    @Test("the pieces cleaned outside a dictation read the same previous piece")
    func cleanedPiecesSeeThePreviousPiece() async {
        let cleaner = finishing()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: reading([]), cleaner: cleaner,
            context: FakeContextEngine(context: Self.document), inserter: FakeTextInserter())
        let heard = ["first piece", "second piece"].map { Transcription(text: $0) }

        _ = await pipeline.clean(heard, seeing: Self.document)

        #expect(cleaner.requests.filter { $0.scope == .piece }.map(\.precedingPiece) == [nil, "first piece"])
    }

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
            text == "First we fix the build Second we review the PR Also the deck is ready.")
    }

    @Test("a correction the speaker made across a pause takes the words it replaced with it")
    func restatementAcrossAPause() async {
        let text = await dictate(
            ["let's meet at four", "no sorry at five", "in the small room"], seeing: Self.document)
        #expect(text == "Let's meet at five. In the small room.")
    }
}
