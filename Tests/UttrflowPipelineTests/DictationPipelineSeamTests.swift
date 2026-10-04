import Foundation
import Synchronization
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// A recogniser that reads out a scripted line per call, so a dictation's pieces are known in advance.
private actor SeamSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private let lines: [String]
    private var calls = 0

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
            segments: [
                TranscriptionSegment(
                    text: lines[calls - 1], start: .zero, end: audio.duration,
                    words: lines[calls - 1].spokenWords.map {
                        TranscribedWord(text: String($0), confidence: 0.2)
                    })
            ],
            audioDuration: audio.duration)
    }
}

/// A language model that answers each piece with the sentence it was scripted for, as a model that punctuates would.
private struct SentenceModel: CleanupModel {
    let answers: [String: String]

    func availability(for language: LanguageCode?) async -> TransformerAvailability { .available }

    func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        guard let answer = answers.first(where: { text.contains($0.key) })?.value else {
            throw .transformFailed(kind: kind, failure: .other)
        }
        return answer
    }
}

private final class SeamInserter: TextInserting, Sendable {
    private let received = Mutex<[String]>([])

    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        received.withLock { $0.append(text) }
        return InsertionAttempt(.accessibility)
    }
}

/// A dictionary fixture that proposes one replacement when all of its spoken words are visible.
private final class SeamCorrector: WordCorrecting, Sendable {
    private let heard: String
    private let wrote: String
    private let entryID = UUID()
    private let state = Mutex<[String]>([])

    init(hearing heard: String, writing wrote: String) {
        self.heard = heard
        self.wrote = wrote
    }

    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> [DictationCorrection] {
        state.withLock { $0.append(transcription.text) }
        let words = transcription.text.spokenWords.map(String.init)
        let wanted = heard.split(whereSeparator: \.isWhitespace).map(String.init)
        guard wanted.count <= words.count,
            let start = (0...(words.count - wanted.count)).first(where: { (index: Int) -> Bool in
                let window: [String] = words[index..<(index + wanted.count)].map {
                    SpokenToken($0).core.lowercased()
                }
                return window == wanted.map { $0.lowercased() }
            })
        else { return [] }
        let range = start..<(start + wanted.count)
        guard let scores = transcription.scoredWords,
            scores[range].allSatisfy({ $0.confidence < 0.5 })
        else { return [] }
        return [
            DictationCorrection(
                heard: heard, wrote: wrote, wordRange: range, entryID: entryID,
                reason: .heardAsSeveralWords, heardConfidence: 0.2)
        ]
    }

    var seen: [String] { state.withLock { $0 } }
}

/// A recording with a clear pause between each of its phrases, cut into one piece per phrase.
private enum SeamTake {
    static let rate = AudioSamples.canonicalSampleRate

    static func tone(_ seconds: Double) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { 0.3 * Float(sin(Double($0) * 0.07)) }
    }

    static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * Double(rate)))
    }

    static func pieces(_ count: Int) -> AudioSamples {
        AudioSamples.canonical(
            Array((0..<count).map { _ in tone(1.2) }.joined(separator: silence(0.5))))
    }
}

/// Windows short enough for a test recording to have several.
private let seamWindows = SpeechWindowing(
    minimumLength: 1, sentencePause: 0.3, comfortableLength: 2, anyPause: 0.2, maximumLength: 5,
    minimumSpeech: 0.2)

// MARK: - Tests

@Suite("Dictation pipeline: the stops at the seams between pieces, through the real cleaner")
struct DictationPipelineSeamTests {
    private static let chat = AppContext.fixture()
    private static let document = AppContext.fixture(
        applicationName: "TextEdit", bundleIdentifier: "com.apple.TextEdit", documentName: "Notes")
    private static let terminal = AppContext.fixture(
        applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal", documentName: "zsh")

    /// One whole dictation, a piece per line, cleaned by `cleaner` against the screen `context` shows.
    private func dictate(
        _ lines: [String], seeing context: AppContext, cleaner: any TranscriptCleaning = rules,
        snippets: any SnippetExpanding = NoTextChanges(),
        corrector: any WordCorrecting = NoTextChanges()
    ) async -> String? {
        await dictateOutcome(
            lines, seeing: context, cleaner: cleaner, snippets: snippets, corrector: corrector)?.text
    }

    private func dictateOutcome(
        _ lines: [String], seeing context: AppContext, cleaner: any TranscriptCleaning = rules,
        snippets: any SnippetExpanding = NoTextChanges(),
        corrector: any WordCorrecting = NoTextChanges(), take: AudioSamples? = nil
    ) async -> DictationOutcome? {
        let take = take ?? SeamTake.pieces(lines.count)
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(take))
        await capture.setCaptured(take)
        let pipeline = DictationPipeline(
            capture: capture, speech: SeamSpeechEngine(lines), cleaner: cleaner,
            context: FakeContextEngine(context: context), inserter: SeamInserter(),
            corrector: corrector,
            snippets: snippets,
            windowing: seamWindows, earlyPoll: .milliseconds(2))

        await pipeline.startRecording()
        await pipeline.finishRecording()
        guard case .inserted(let outcome) = await pipeline.currentState else { return nil }
        return outcome
    }

    /// The shipping floor: the deterministic passes, with no model in front of them.
    private static let rules = TransformerRouter(
        engines: [RuleBasedTransformer()], preference: [.rules])

    /// The shipping model engine over a model scripted to answer each piece, with the floor beneath it.
    private static func model(_ answers: [String: String]) -> TransformerRouter {
        TransformerRouter(
            engines: [
                GenerativeTextTransformer(kind: .foundationModels, model: SentenceModel(answers: answers)),
                RuleBasedTransformer(),
            ],
            preference: [.foundationModels, .rules])
    }

    @Test("a chat message cut at its sentence ends keeps the stop at every seam and its final one")
    func longChatMessageKeepsItsSeams() async {
        let text = await dictate(
            ["I left the office.", "The traffic is bad.", "I will be late."], seeing: Self.chat)
        #expect(text == "I left the office. The traffic is bad. I will be late.")
    }

    @Test("a short chat message in two pieces keeps the stop between them and drops only the last")
    func shortChatMessageKeepsItsSeam() async {
        let text = await dictate(["On my way.", "Be there soon."], seeing: Self.chat)
        #expect(text == "On my way. Be there soon")
    }

    /// Speech with no pause at all, so only the microphone change can end the first piece.
    @Test("a microphone change mid-speech keeps the words on both sides, recognised apart")
    func microphoneChangeKeepsBothSides() async throws {
        let speech = SeamTake.tone(4)
        let change = speech.count * 2 / 5
        let take = AudioSamples.canonical(speech, discontinuities: [change])

        let outcome = try #require(
            await dictateOutcome(["On my way.", "Be there soon."], seeing: Self.chat, take: take))

        #expect(outcome.text == "On my way. Be there soon")
    }

    @Test("a seam the recogniser left unmarked is still a sentence end in a chat")
    func unmarkedSeamInAChat() async {
        let text = await dictate(["on my way", "be there soon"], seeing: Self.chat)
        #expect(text == "On my way. Be there soon")
    }

    @Test("a question at a seam keeps its mark and the message still reads as sentences")
    func questionAtASeam() async {
        let text = await dictate(
            ["Can you bring the charger?", "I left mine at home.", "See you soon."], seeing: Self.chat)
        #expect(text == "Can you bring the charger? I left mine at home. See you soon.")
    }

    @Test("the model's answers keep their seams in a chat, not only the rules'")
    func modelAnswersKeepTheirSeams() async {
        let cleaner = Self.model([
            "left the office": "I left the office.", "traffic": "The traffic is bad.",
            "late": "I will be late.",
        ])
        let text = await dictate(
            ["i left the office", "the traffic is bad", "i will be late"], seeing: Self.chat,
            cleaner: cleaner)
        #expect(text == "I left the office. The traffic is bad. I will be late.")
    }

    @Test("a document stops every seam and the end, as it always has")
    func documentIsUnchanged() async {
        let text = await dictate(
            ["i left the office", "the traffic is bad", "i will be late"], seeing: Self.document)
        #expect(text == "I left the office. The traffic is bad. I will be late.")
    }

    @Test("joins a dependent clause spoken as one piece to its main clause in the next")
    func dependentClauseContinuesAcrossARecognizerPiece() async {
        let text = await dictate(
            ["When the light was finally automated.", "The logbook was given to the town museum."],
            seeing: Self.document)

        #expect(text == "When the light was finally automated the logbook was given to the town museum.")
    }

    @Test("a terminal takes no stop at a seam or at the end, even one the recogniser wrote")
    func terminalTakesNoStops() async {
        let text = await dictate(["git status.", "git diff."], seeing: Self.terminal)
        #expect(text?.contains(".") == false)
    }

    /// A terminal's seam is no sentence end, so the second piece is cased as it would be in one breath.
    @Test("a terminal cases the words after a seam as it would have in one breath")
    func terminalSeamIsNotASentenceStart() async {
        let text = await dictate(["git status.", "git diff."], seeing: Self.terminal)
        #expect(text == "git status git diff")
    }

    @Test("the caret's mid-sentence case applies to the message's first word, not to every piece's")
    func midSentenceCaretCasesOnlyTheFirstWord() async {
        let context = AppContext.fixture(
            applicationName: "TextEdit", bundleIdentifier: "com.apple.TextEdit", documentName: "Notes",
            precedingText: "We stopped because ")
        let text = await dictate(["the build failed.", "The tests are red."], seeing: context)
        #expect(text == "the build failed. The tests are red.")
    }

    @Test("each reported snippet trigger expands when its words cross a piece seam")
    func snippetsExpandAcrossPieceSeams() async {
        let examples: [([String], String, String)] = [
            (["please send it to my home", "address"], "my home address", "12 Invented Lane"),
            (["please send it to my", "home address"], "my home address", "12 Invented Lane"),
            (["here is the meeting", "link"], "meeting link", "https://example.test/meeting"),
            (["thanks for your help sign", "off"], "sign off", "Regards, Asha"),
            (["my email", "address is below"], "my email address", "asha@example.test"),
        ]
        for (pieces, trigger, replacement) in examples {
            let expander = SeamSnippetExpander(trigger: trigger, expansion: replacement)
            let text = await dictate(pieces, seeing: Self.document, snippets: expander)
            #expect(text?.contains(replacement) == true)
            #expect(text?.contains(trigger) == false)
        }
    }

    @Test("a speaker's full stop inside one piece still separates a snippet trigger")
    func spokenStopStillSeparatesSnippetTrigger() async {
        let expander = SeamSnippetExpander(
            trigger: "meeting link", expansion: "https://example.test/meeting")
        let text = await dictate(["here is the meeting. Link"], seeing: Self.document, snippets: expander)
        #expect(text?.contains("meeting. Link") == true)
        #expect(text?.contains("https://example.test/meeting") == false)
    }

    @Test("a dictionary term split at a piece seam is corrected as one range")
    func paymentSheetCrossesSeam() async {
        let corrector = SeamCorrector(hearing: "payment sheet", writing: "PaymentSheet")
        let outcome = await dictateOutcome(
            ["I opened payment", "sheet today"], seeing: Self.document, corrector: corrector)

        #expect(corrector.seen.contains("I opened payment sheet today"))
        #expect(outcome?.text == "I opened PaymentSheet today")
        #expect(outcome?.changes.corrections.map(\.wordRange) == [2..<4])
    }

    @Test("the product spelling is corrected across a piece seam")
    func uttrflowCrossesSeam() async {
        let corrector = SeamCorrector(hearing: "utter flow", writing: "Uttrflow")
        let outcome = await dictateOutcome(
            ["we use utter", "flow daily"], seeing: Self.document, corrector: corrector)

        #expect(corrector.seen.contains("we use utter flow daily"))
        #expect(outcome?.text == "We use Uttrflow daily")
        #expect(outcome?.changes.corrections.map(\.wordRange) == [2..<4])
    }

    @Test("an initialism is corrected across a piece seam")
    func sqlCrossesSeam() async {
        let corrector = SeamCorrector(hearing: "s q l", writing: "SQL")
        let outcome = await dictateOutcome(
            ["run the s q", "l migration"], seeing: Self.document, corrector: corrector)

        #expect(corrector.seen.contains("run the s q l migration"))
        #expect(outcome?.text == "Run the SQL migration")
        #expect(outcome?.changes.corrections.map(\.wordRange) == [2..<5])
    }

    @Test("a dictionary term already together within a piece keeps the same stop and correction")
    func paymentSheetWithinPieceIsUnchanged() async {
        let corrector = SeamCorrector(hearing: "payment sheet", writing: "PaymentSheet")
        let outcome = await dictateOutcome(
            ["I opened payment sheet", "today"], seeing: Self.document, corrector: corrector)

        #expect(outcome?.text == "I opened PaymentSheet. Today")
        #expect(outcome?.changes.corrections.map(\.wordRange) == [2..<4])
    }
}

private struct SeamSnippetExpander: SnippetExpanding {
    let trigger: String
    let expansion: String

    func expand(_ text: String) async -> ExpandedTranscript {
        let result = SnippetExpander(snippets: [
            Snippet(trigger: trigger, expansion: expansion, created: Date(timeIntervalSince1970: 0))
        ]).expand(text)
        return ExpandedTranscript(
            text: result.text,
            snippets: result.applied.map {
                SnippetUse(snippetID: $0.snippetID, matched: $0.matched, expansion: $0.expansion)
            })
    }
}
