import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
import UttrflowDictionary
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// A tidier that records every request and hands the words back unchanged.
private final class WatchingCleaner: TranscriptCleaning, Sendable {
    /// The account every tidy hands back; nil keeps none, as most tests need.
    private let account: CleaningRecord?
    private let state = Mutex(
        (requests: [TransformationRequest](), warmed: [Destination?](), finalReservations: Int()))

    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        state.withLock { $0.requests.append(request) }
        return TransformationResult(
            text: request.transcription.text, producedBy: .rules, cleaning: account)
    }

    init(account: CleaningRecord? = nil) {
        self.account = account
    }

    func warm(for situation: Situation?) async {
        state.withLock { $0.warmed.append(situation?.destination) }
    }

    func reserveFinalPiece(_ situation: Situation?) async {
        state.withLock { $0.finalReservations += 1 }
    }

    var requests: [TransformationRequest] { state.withLock(\.requests) }
    var destinations: [Destination] { requests.map(\.situation.destination) }
    var finalReservations: Int { state.withLock(\.finalReservations) }
}

/// A screen that will not answer the first time until the test says so, and answers with somewhere else after that.
private actor GatedContextEngine: ContextEngine {
    private let first: AppContext
    private let then: AppContext
    private let gate: AsyncStream<Void>
    private let opener: AsyncStream<Void>.Continuation
    private(set) var reads = 0
    /// Fires each time a read answers.
    let answered = Signal()

    init(first: AppContext, then: AppContext) {
        self.first = first
        self.then = then
        (gate, opener) = AsyncStream.makeStream()
    }

    func currentContext() async -> AppContext {
        reads += 1
        guard reads == 1 else {
            answered.fire()
            return then
        }
        for await _ in gate { break }
        answered.fire()
        return first
    }

    func release() {
        opener.yield()
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

/// A dictionary that knows one word for its first read only, as a removal mid-dictation does.
private final class ChangingDictionary: Sendable {
    private let reads = Mutex(0)
    private let entry = DictionaryEntry(
        word: "Uttrflow", pronunciation: "utter flow", origin: .added, firstSeen: .distantPast)

    func index() -> PhoneticIndex {
        let before = reads.withLock { count in
            defer { count += 1 }
            return count
        }
        return PhoneticIndex(entries: before == 0 ? [entry] : [])
    }

    var readCount: Int { reads.withLock { $0 } }
}

/// A dictionary the person edits between reads: the opening word is removed, one is added and one is learnt.
private final class EditedDictionary: Sendable {
    private let reads = Mutex(0)
    static let opening = PhoneticIndex(entries: [
        DictionaryEntry(
            word: "Uttrflow", pronunciation: "utter flow", origin: .added, firstSeen: .distantPast)
    ])
    private static let edited = PhoneticIndex(entries: [
        DictionaryEntry(
            word: "Zorvex", pronunciation: "sore vex", origin: .added, firstSeen: .distantPast),
        DictionaryEntry(
            word: "Kelmar", pronunciation: "kel mar", origin: .learned, firstSeen: .distantPast),
    ])

    func index() -> PhoneticIndex {
        let before = reads.withLock { count in
            defer { count += 1 }
            return count
        }
        return before == 0 ? Self.opening : Self.edited
    }

    var readCount: Int { reads.withLock { $0 } }
}

/// Prompt words that change on every ranking, as a dictionary edited mid-dictation would make them.
private final class ShiftingWords: Sendable {
    private let calls = Mutex(0)

    func words() -> [String] {
        calls.withLock { count in
            defer { count += 1 }
            return count == 0 ? ["Uttrflow"] : ["Zorvex", "Kelmar"]
        }
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
    static let threePieces = AudioSamples.canonical(
        tone(1.2) + silence(0.5) + tone(1.2) + silence(0.5) + tone(1.2))
    static let onePiece = AudioSamples.canonical(tone(1.0))
}

/// Windows short enough for a test recording to have two.
private let quick = SpeechWindowing(
    minimumLength: 1, sentencePause: 0.3, comfortableLength: 2, anyPause: 0.2, maximumLength: 5,
    minimumSpeech: 0.2)

extension DictationState {
    fileprivate var outcome: DictationOutcome? {
        if case .inserted(let outcome) = self { outcome } else { nil }
    }
}

// MARK: - Tests

@Suite("Dictation pipeline: the settings a dictation runs under", .timeLimit(.minutes(1)))
struct DictationPipelineSettingsTests {
    private let slack = AppContext.fixture(
        applicationName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap",
        documentName: "#engineering")

    /// A recogniser that hands back `texts` in order, repeating the last.
    private func pieces(_ texts: [String]) -> FakeSpeechEngine {
        FakeSpeechEngine(
            transcribing: .successes(texts.map { Transcription(text: $0, audioDuration: .seconds(1)) }))
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
            speech: pieces(["first, check the logs", "second, restart the box"]),
            cleaner: cleaner,
            context: FakeContextEngine(context: slack),
            inserter: FakeTextInserter(),
            destinationOverrides: overrides,
            windowing: quick)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(cleaner.destinations == [.document, .document], "every piece is tidied for the override")
        #expect(cleaner.finalReservations == 1, "the last piece reserves the warmed session")
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
            speech: pieces(["ship it"]),
            cleaner: started,
            context: FakeContextEngine(context: slack),
            inserter: FakeTextInserter(),
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
    func earlyReadCannotOutliveItsDictation() async throws {
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
            speech: pieces(["ship it"]),
            cleaner: cleaner,
            context: context,
            inserter: FakeTextInserter(),
            windowing: quick,
            earlyPoll: .seconds(60))

        await pipeline.startRecording()
        // The abandoned read must be at the screen before the cancel, or the second dictation's read is the held one.
        try await eventually { await context.reads == 1 }
        await pipeline.cancel()
        await pipeline.startRecording()
        // The second dictation reads its own screen; only then is the abandoned read let go.
        try await arrival(of: context.answered.fired)
        await context.release()
        // Both reads kept or dropped, so the abandoned one has had its chance to land.
        try await eventually { await pipeline.earlyReadsSettled >= 2 }
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.outcome?.insertedInto == "Notes")
        #expect(cleaner.destinations == [.document], "Notes, not the spreadsheet nobody dictated into")
    }

    /// The user starts in one app and switches while the words are being transcribed; they land in the second.
    @Test("files the dictation under the application the insertion wrote into")
    func recordsWhereTheWordsLanded() async {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.onePiece))
        let pipeline = DictationPipeline(
            capture: capture,
            speech: pieces(["ship it"]),
            cleaner: WatchingCleaner(),
            context: FakeContextEngine(
                context: .fixture(
                    applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal",
                    documentName: "zsh")),
            inserter: FakeTextInserter(
                .success(
                    InsertionAttempt(
                        .accessibility,
                        destination: InsertionDestination(
                            applicationName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap")))),
            windowing: quick,
            earlyPoll: .seconds(60))

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.outcome?.insertedInto == "Slack")
        #expect(
            await pipeline.currentState.outcome?.insertedIntoIdentifier
                == "com.tinyspeck.slackmacgap")
    }

    /// A route that cannot say where it wrote leaves the recording's read as the best answer there is.
    @Test("keeps the recording's reading when the insertion cannot say")
    func keepsTheRecordingsReadingWhenUnknown() async {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.onePiece))
        let pipeline = DictationPipeline(
            capture: capture,
            speech: pieces(["ship it"]),
            cleaner: WatchingCleaner(),
            context: FakeContextEngine(
                context: .fixture(
                    applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal",
                    documentName: "zsh")),
            inserter: FakeTextInserter(),
            windowing: quick,
            earlyPoll: .seconds(60))

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.outcome?.insertedInto == "Terminal")
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
            speech: FakeSpeechEngine(transcribing: .successes([heard])),
            cleaner: cleaner,
            context: FakeContextEngine(context: slack),
            inserter: FakeTextInserter(),
            corrector: FixedCorrector(
                correction: DictationCorrection(
                    heard: "payment sheet", wrote: "PaymentSheet", wordRange: 4..<6,
                    entryID: UUID(), reason: .heardAsSeveralWords, heardConfidence: 0.2)),
            windowing: quick)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        let request = cleaner.requests.first
        #expect(request?.transcription.text == "clear the cash in PaymentSheet")
        let draft = Draft(transcription: request?.transcription ?? Transcription(text: ""))
        #expect(draft.confidencesAreReal, "the doubtful words survive the dictionary's correction")
        #expect(draft.words.map(\.text) == ["clear", "the", "cash", "in", "PaymentSheet"])
        #expect(draft.words[2].confidence == 0.3, "the half-heard word is still half-heard")
        #expect(draft.words[4].confidence == 0.2, "the settled word keeps the score it was heard with")
        #expect(draft.words[4].settled, "the word the dictionary settled is not rewritten")
    }

    /// Every piece of one dictation is corrected against the dictionary held at its start.
    @Test("a dictionary changed while the user is speaking does not change that dictation")
    func dictionaryIsFixedForTheDictation() async {
        let dictionary = ChangingDictionary()
        let cleaner = WatchingCleaner()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.twoPieces)),
            speech: FakeSpeechEngine(
                transcribing: .successes([doubted(Self.said), doubted(Self.said)])),
            cleaner: cleaner,
            context: FakeContextEngine(context: slack),
            inserter: FakeTextInserter(),
            corrector: DictionaryCorrections { _ in dictionary.index() },
            windowing: quick)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(
            cleaner.requests.map(\.transcription.text) == [Self.wrote, Self.wrote],
            "the second piece still knows the word held at the start")
        #expect(dictionary.readCount == 1, "the dictionary is read once per dictation")
    }

    /// Adding, removing and learning words while three pieces are decoded leaves every piece on one revision.
    @Test("a three-piece dictation decodes and corrects every piece against the revision it started with")
    func threePiecesShareOneRevision() async {
        let dictionary = EditedDictionary()
        let ranking = ShiftingWords()
        let cleaner = WatchingCleaner(
            account: CleaningRecord(changes: [CleaningRecord.Change(step: .fillers, removed: ["um"])]))
        let recorder = CollectingCleaningRecorder()
        let speech = FakeSpeechEngine(
            transcribing: .successes([doubted(Self.said), doubted(Self.said), doubted(Self.said)]))
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces)),
            speech: speech,
            cleaner: cleaner,
            context: FakeContextEngine(context: slack),
            inserter: FakeTextInserter(),
            speechWords: { _ in ranking.words() },
            corrector: DictionaryCorrections { _ in dictionary.index() },
            cleaningRecorder: recorder,
            windowing: quick)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        let calls = await speech.transcribeCalls.events
        #expect(calls.count == 3, "the recording is decoded as three pieces")
        #expect(
            Set(calls.map(\.options.vocabulary)) == [["Uttrflow"]],
            "every piece is decoded with the words ranked at the start")
        #expect(
            cleaner.requests.map(\.transcription.text) == [Self.wrote, Self.wrote, Self.wrote],
            "every piece is corrected with the word held at the start")
        #expect(dictionary.readCount == 1, "the dictionary is read once per dictation")
        #expect(
            await recorder.records.map(\.dictionaryRevision) == [EditedDictionary.opening.revision],
            "the record names the revision every piece used")
    }

    private static let said = "Uttrflow works offline and the point of ?utter ?flow is that nothing leaves"
    private static let wrote = "Uttrflow works offline and the point of Uttrflow is that nothing leaves"

    /// A transcript scored word by word, a word marked `?` doubted.
    private func doubted(_ marked: String) -> Transcription {
        let words = marked.split(separator: " ").map {
            TranscribedWord(
                text: $0.replacingOccurrences(of: "?", with: ""), confidence: $0.hasPrefix("?") ? 0.2 : 1)
        }
        let text = words.map(\.text).joined(separator: " ")
        return Transcription(
            text: text,
            segments: [TranscriptionSegment(text: text, start: .zero, end: .seconds(1), words: words)],
            audioDuration: .seconds(1))
    }
}
