import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// A recogniser that hands back the scripted pieces in order, repeating the last one.
private actor ScriptedSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private let pieces: [Transcription]
    private(set) var calls = 0

    init(_ pieces: [Transcription]) {
        self.pieces = pieces
    }

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        calls += 1
        return pieces[min(calls - 1, pieces.count - 1)]
    }
}

/// A tidier that records every request and hands the words back unchanged.
private final class WatchingCleaner: TranscriptCleaning, Sendable {
    private let state = Mutex((requests: [TransformationRequest](), warmed: [Destination?]()))

    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        state.withLock { $0.requests.append(request) }
        return TransformationResult(text: request.transcription.text, producedBy: .rules)
    }

    func warm(for situation: Situation?) async {
        state.withLock { $0.warmed.append(situation?.destination) }
    }

    var requests: [TransformationRequest] { state.withLock(\.requests) }
    var destinations: [Destination] { requests.map(\.situation.destination) }
}

/// A screen that will not answer the first time until the test says so, and answers with somewhere else after that.
private actor GatedContextEngine: ContextEngine {
    private let first: AppContext
    private let then: AppContext
    private var open = false
    private(set) var reads = 0
    private(set) var answered = 0

    init(first: AppContext, then: AppContext) {
        self.first = first
        self.then = then
    }

    func currentContext() async -> AppContext {
        reads += 1
        guard reads == 1 else {
            answered += 1
            return then
        }
        while !open { try? await Task.sleep(for: .milliseconds(1)) }
        answered += 1
        return first
    }

    func release() {
        open = true
    }
}

/// A place for the words to land that never refuses.
private struct QuietInserter: TextInserting {
    func insert(_ text: String) async throws(TextInsertionError) -> TextInsertionMethod {
        .accessibility
    }
}

/// A dictionary that always proposes the same correction.
private struct FixedCorrector: WordCorrecting {
    let correction: DictationCorrection

    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> [DictationCorrection] {
        [correction]
    }
}

// MARK: - Fixtures

private enum Take {
    static let rate = AudioSamples.canonicalSampleRate

    static func tone(_ seconds: Double) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { 0.3 * Float(sin(Double($0) * 0.07)) }
    }

    static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * Double(rate)))
    }

    /// Two phrases with a clear pause between them.
    static let twoPieces = AudioSamples.canonical(tone(1.2) + silence(0.5) + tone(1.2))
    static let onePiece = AudioSamples.canonical(tone(1.0))
}

/// Windows short enough for a test recording to have two.
private let quick = SpeechWindowing(
    minimumLength: 1, sentencePause: 0.3, comfortableLength: 2, anyPause: 0.2, maximumLength: 5)

extension DictationState {
    fileprivate var outcome: DictationOutcome? {
        if case .inserted(let outcome) = self { outcome } else { nil }
    }
}

// MARK: - Tests

@Suite("Dictation pipeline: the settings a dictation runs under")
struct DictationPipelineSettingsTests {
    private let slack = AppContext.fixture(
        applicationName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap",
        documentName: "#engineering")

    private func pieces(_ texts: [String]) -> [Transcription] {
        texts.map { Transcription(text: $0, audioDuration: .seconds(1)) }
    }

    /// A long dictation is laid out when its pieces are joined, and that is where the override was missing.
    @Test("an app treated as somewhere else is treated that way by a dictation of several pieces too")
    func overrideReachesTheJoin() async {
        let overrides = DestinationOverrides.none.setting(
            .document, for: "com.tinyspeck.slackmacgap", named: "Slack")
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.twoPieces))
        let cleaner = WatchingCleaner()
        let pipeline = DictationPipeline(
            capture: capture,
            speech: ScriptedSpeechEngine(pieces(["first check the logs", "second restart the box"])),
            cleaner: cleaner,
            context: FakeContextEngine(context: slack),
            inserter: QuietInserter(),
            destinationOverrides: overrides,
            windowing: quick)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(cleaner.destinations == [.document, .document], "every piece is tidied for the override")
        #expect(
            await pipeline.currentState.outcome?.text == "- Check the logs\n- Restart the box",
            "the pieces are joined under the override's formatter, which lays out a list")
    }

    /// The clean-up steps and the overrides are promised for the next dictation, not the one being spoken.
    @Test("a setting changed while the user is speaking does not change that dictation")
    func settingsLandOnTheNextDictation() async {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.onePiece))
        let started = WatchingCleaner()
        let adopted = WatchingCleaner()
        let pipeline = DictationPipeline(
            capture: capture,
            speech: ScriptedSpeechEngine(pieces(["ship it"])),
            cleaner: started,
            context: FakeContextEngine(context: slack),
            inserter: QuietInserter(),
            windowing: quick,
            earlyPoll: .seconds(60))

        await pipeline.startRecording()
        await pipeline.adopt(
            cleaner: adopted,
            destinationOverrides: DestinationOverrides.none.setting(
                .document, for: "com.tinyspeck.slackmacgap", named: "Slack"))
        await pipeline.finishRecording()

        #expect(adopted.requests.isEmpty, "the tidier adopted mid-dictation waits for the next one")
        #expect(started.destinations == [.messaging], "and so does the override adopted with it")

        await pipeline.acknowledge()
        await pipeline.startRecording()
        await pipeline.finishRecording()
        #expect(adopted.destinations == [.document], "the dictation after it runs the new choices")
    }

    /// The screen read for a dictation the user gave up on must not decide the words of the next one.
    @Test("a screen read for an abandoned dictation does not land in the one that follows it")
    func earlyReadCannotOutliveItsDictation() async {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.onePiece))
        await capture.setCaptured(Take.onePiece)
        let cleaner = WatchingCleaner()
        let context = GatedContextEngine(
            first: .fixture(
                applicationName: "Numbers", bundleIdentifier: "com.apple.iWork.Numbers",
                documentName: "Budget"),
            then: .fixture(
                applicationName: "Notes", bundleIdentifier: "com.apple.Notes", documentName: "Ideas"))
        let pipeline = DictationPipeline(
            capture: capture,
            speech: ScriptedSpeechEngine(pieces(["ship it"])),
            cleaner: cleaner,
            context: context,
            inserter: QuietInserter(),
            windowing: quick,
            earlyPoll: .seconds(60))

        await pipeline.startRecording()
        await pipeline.cancel()
        await pipeline.startRecording()
        // The second dictation reads its own screen; only then is the abandoned read let go.
        while await context.answered < 1 { try? await Task.sleep(for: .milliseconds(1)) }
        await context.release()
        while await context.answered < 2 { try? await Task.sleep(for: .milliseconds(1)) }
        try? await Task.sleep(for: .milliseconds(50))
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.outcome?.insertedInto == "Notes")
        #expect(cleaner.destinations == [.document], "Notes, not the spreadsheet nobody dictated into")
    }

    /// A word the dictionary settled is certain; every other word keeps the score it was heard with.
    @Test("a dictionary correction leaves the recogniser's confidences intact for the rest of the piece")
    func correctionKeepsTheConfidences() async {
        let words = [
            TranscribedWord(text: "clear", confidence: 0.9),
            TranscribedWord(text: " the", confidence: 0.9),
            TranscribedWord(text: " cash", confidence: 0.3),
            TranscribedWord(text: " in", confidence: 0.9),
            TranscribedWord(text: " payment", confidence: 0.2),
            TranscribedWord(text: " sheet", confidence: 0.2),
        ]
        let heard = Transcription(
            text: "clear the cash in payment sheet",
            segments: [
                TranscriptionSegment(
                    text: "clear the cash in payment sheet", start: .zero, end: .seconds(2),
                    words: words)
            ],
            audioDuration: .seconds(2))
        let cleaner = WatchingCleaner()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.onePiece)),
            speech: ScriptedSpeechEngine([heard]),
            cleaner: cleaner,
            context: FakeContextEngine(context: slack),
            inserter: QuietInserter(),
            corrector: FixedCorrector(
                correction: DictationCorrection(
                    heard: "payment sheet", wrote: "PaymentSheet", wordRange: 4..<6,
                    entryID: UUID(), reason: "heardAsSeveralWords", heardConfidence: 0.2)),
            windowing: quick)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        let request = cleaner.requests.first
        #expect(request?.transcription.text == "clear the cash in PaymentSheet")
        let draft = Draft(transcription: request?.transcription ?? Transcription(text: ""))
        #expect(draft.confidencesAreReal, "the doubtful words survive the dictionary's correction")
        #expect(draft.words.map(\.text) == ["clear", "the", "cash", "in", "PaymentSheet"])
        #expect(draft.words[2].confidence == 0.3, "the half-heard word is still half-heard")
        #expect(draft.words[4].confidence == 1, "the word the dictionary settled is not doubtful")
    }
}
