import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// An inserter that answers a scripted attempt, or refuses.
private final class ScriptedInserter: TextInserting, Sendable {
    private let secure: Bool
    private let refuses: Bool

    init(secure: Bool = false, refuses: Bool = false) {
        self.secure = secure
        self.refuses = refuses
    }

    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        guard !refuses else { throw .clipboardUnavailable }
        return InsertionAttempt(.pasteboard, intoSecureField: secure)
    }
}

/// A vocabulary that remembers every lesson it is offered.
private final class RememberingVocabulary: VocabularyLearning, Sendable {
    private let lessons = Mutex<[String]>([])

    func learn(
        heard: String, wrote: String, seeing context: AppContext
    ) async throws(DictationChangeError) {
        lessons.withLock { $0.append(wrote) }
    }

    var offered: [String] { lessons.withLock { $0 } }
}

/// Keeps every account of the clean-up it is handed.
private actor RememberingCleaningRecorder: CleaningRecording {
    private(set) var records: [CleaningRecord] = []

    func record(_ record: CleaningRecord) async { records.append(record) }
}

/// A tidier that leaves the words alone and reports one account, so its recording can be seen.
private struct AccountingCleaner: TranscriptCleaning {
    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        TransformationResult(
            text: request.transcription.text, producedBy: .rules,
            cleaning: CleaningRecord(changes: [CleaningRecord.Change(step: .fillers, removed: ["um"])]))
    }
}

/// A recogniser that hears the first piece and fails every later one, so words are lost after the screen is read.
private actor FailingAfterFirstSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private var calls = 0

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        calls += 1
        guard calls == 1 else { throw .transcriptionFailed(description: "scripted") }
        return Transcription(text: "open", audioDuration: audio.duration)
    }
}

private let passphrase = "correct horse battery staple"
private let secureScreen = AppContext(applicationName: "Keychain Access", isSecure: true)

private func makePipeline(
    context: AppContext = secureScreen,
    inserter: any TextInserting = ScriptedInserter(),
    vocabulary: any VocabularyLearning = NoTextChanges(),
    cleaner: any TranscriptCleaning = AccountingCleaner(),
    cleaningRecorder: any CleaningRecording = NoOpCleaningRecorder(),
    recordings: any RecordingKeeper = RecordingsNotKept()
) -> DictationPipeline {
    DictationPipeline(
        capture: FakeAudioCaptureEngine(),
        speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: passphrase))),
        cleaner: cleaner,
        context: FakeContextEngine(context: context),
        inserter: inserter,
        vocabulary: vocabulary,
        cleaningRecorder: cleaningRecorder,
        recordings: recordings,
        clock: ManualClock())
}

private func dictate(with pipeline: DictationPipeline) async -> DictationState {
    await pipeline.startRecording()
    await pipeline.finishRecording()
    return await pipeline.currentState
}

@Suite("Dictation into a secure field keeps the words nowhere")
struct DictationSecureFieldTests {
    @Test("a secure screen read still inserts the words, and marks them as kept nowhere")
    func secureScreenIsMarked() async throws {
        let state = await dictate(with: makePipeline())

        guard case .inserted(let outcome) = state else {
            Issue.record("expected an insertion, got \(state)")
            return
        }
        #expect(outcome.text == passphrase)
        #expect(outcome.intoSecureField)
        #expect(outcome.wordsToKeep == nil)
    }

    @Test("a field found secure just before the write is marked though the screen read was not")
    func secureAtInsertionIsMarked() async throws {
        let state = await dictate(
            with: makePipeline(context: .fixture(), inserter: ScriptedInserter(secure: true)))

        guard case .inserted(let outcome) = state else {
            Issue.record("expected an insertion, got \(state)")
            return
        }
        #expect(outcome.intoSecureField)
        #expect(outcome.wordsToKeep == nil)
    }

    @Test("an ordinary field's words are kept as before")
    func ordinaryWordsAreKept() async throws {
        let state = await dictate(with: makePipeline(context: .fixture()))

        guard case .inserted(let outcome) = state else {
            Issue.record("expected an insertion, got \(state)")
            return
        }
        #expect(outcome.intoSecureField == false)
        #expect(outcome.wordsToKeep == passphrase)
    }

    @Test("the dictionary learns nothing from a secure field")
    func learnsNothing() async {
        let vocabulary = RememberingVocabulary()
        _ = await dictate(with: makePipeline(vocabulary: vocabulary))

        #expect(vocabulary.offered.isEmpty)
    }

    @Test("the dictionary learns nothing from a field found secure only at the write")
    func learnsNothingWhenSecureAtInsertion() async {
        let vocabulary = RememberingVocabulary()
        _ = await dictate(
            with: makePipeline(
                context: .fixture(), inserter: ScriptedInserter(secure: true), vocabulary: vocabulary))

        #expect(vocabulary.offered.isEmpty)
    }

    @Test("the dictionary still learns from an ordinary field")
    func learnsFromOrdinary() async {
        let vocabulary = RememberingVocabulary()
        _ = await dictate(with: makePipeline(context: .fixture(), vocabulary: vocabulary))

        #expect(vocabulary.offered == [passphrase])
    }

    @Test("no account of the clean-up is kept for a secure field")
    func keepsNoCleaningAccount() async {
        let recorder = RememberingCleaningRecorder()
        _ = await dictate(with: makePipeline(cleaningRecorder: recorder))

        #expect(await recorder.records.isEmpty)
    }

    @Test("an ordinary field's clean-up account is still kept")
    func keepsOrdinaryCleaningAccount() async {
        let recorder = RememberingCleaningRecorder()
        _ = await dictate(with: makePipeline(context: .fixture(), cleaningRecorder: recorder))

        #expect(await recorder.records.count == 1)
    }

    @Test("a refused insertion into a secure field salvages nothing a history may keep")
    func failedInsertionKeepsNothing() async throws {
        let state = await dictate(with: makePipeline(inserter: ScriptedInserter(refuses: true)))

        guard case .failed(let failure) = state else {
            Issue.record("expected a failure, got \(state)")
            return
        }
        #expect(failure.intoSecureField)
        #expect(failure.wordsToKeep == nil)
    }

    @Test("a refused insertion into an ordinary field still salvages the words")
    func failedOrdinaryInsertionKeepsWords() async throws {
        let state = await dictate(
            with: makePipeline(context: .fixture(), inserter: ScriptedInserter(refuses: true)))

        guard case .failed(let failure) = state else {
            Issue.record("expected a failure, got \(state)")
            return
        }
        #expect(failure.intoSecureField == false)
        #expect(failure.wordsToKeep == passphrase)
    }

    @Test("a secure field's audio is not kept for a retry when its words are lost")
    func lostWordsKeepNoAudio() async throws {
        let recording = KeptRecording(id: UUID(), when: Date(), duration: .seconds(3))
        let recordings = FakeRecordingKeeper(current: recording)
        let rate = AudioSamples.canonicalSampleRate
        let tone = (0..<Int(1.2 * Double(rate))).map { 0.3 * Float(sin(Double($0) * 0.07)) }
        let silence = [Float](repeating: 0, count: rate / 2)
        let take = AudioSamples.canonical(tone + silence + tone + silence + tone)
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(take))
        await capture.setCaptured(take)
        let pipeline = DictationPipeline(
            capture: capture, speech: FailingAfterFirstSpeechEngine(), cleaner: AccountingCleaner(),
            context: FakeContextEngine(context: secureScreen), inserter: ScriptedInserter(),
            recordings: recordings, clock: ManualClock(),
            windowing: SpeechWindowing(
                minimumLength: 1, sentencePause: 0.3, comfortableLength: 2, anyPause: 0.2,
                maximumLength: 5))

        let state = await dictate(with: pipeline)

        guard case .failed(let failure) = state else {
            Issue.record("expected a failure, got \(state)")
            return
        }
        #expect(failure.transcript == nil)
        #expect(failure.recovery != .retryFromRecording)
        #expect(await recordings.discarded == [recording.id])
    }

    @Test("marking a failure secure survives offering it another next step")
    func markingSurvivesOffering() {
        let failure = DictationFailure(
            message: "Nope", recovery: .retry, severity: .recoverable, transcript: passphrase
        ).markingSecure(true).offering(.pasteManually)

        #expect(failure.intoSecureField)
        #expect(failure.recovery == .pasteManually)
        #expect(failure.wordsToKeep == nil)
    }
}

@Suite("The floating button shows none of a secure field's words")
struct SecureFieldDockTests {
    private let secureOutcome = DictationOutcome(
        text: passphrase, method: .accessibility, cleanedBy: .rules, intoSecureField: true)

    @Test("an insertion into a secure field draws no preview and reads none aloud")
    func insertedHidesWords() {
        let drawn = DictationPresenter.dock(for: .inserted(secureOutcome))

        #expect(drawn.primaryLine == "Inserted")
        #expect(drawn.secondaryLine == nil)
        #expect(!drawn.accessibilityLabel.contains(passphrase))
    }

    @Test("every insertion route hides a secure field's words")
    func everyRouteHidesWords() {
        let routes = [
            DictationOutcome(
                text: passphrase, method: .clipboard, cleanedBy: .rules, fromRecording: true,
                intoSecureField: true),
            DictationOutcome(
                text: passphrase, method: .clipboard, cleanedBy: .rules, intoSecureField: true),
            DictationOutcome(
                text: passphrase, method: .pasteboard, cleanedBy: .rules, arrival: .unconfirmed,
                intoSecureField: true),
        ]
        for outcome in routes {
            let drawn = DictationPresenter.dock(for: .inserted(outcome))
            #expect(drawn.secondaryLine?.contains("correct horse") != true)
            #expect(!drawn.accessibilityLabel.contains(passphrase))
        }
    }

    @Test("a failure meant for a secure field shows none of the salvaged words")
    func failureHidesWords() {
        let failure = DictationFailure(
            message: "Nope", recovery: .pasteManually, severity: .degraded, transcript: passphrase,
            intoSecureField: true)

        #expect(DictationPresenter.dock(for: .failed(failure)).secondaryLine == nil)
    }

    @Test("an ordinary insertion still shows its words")
    func ordinaryShowsWords() {
        let outcome = DictationOutcome(text: passphrase, method: .accessibility, cleanedBy: .rules)

        #expect(DictationPresenter.dock(for: .inserted(outcome)).secondaryLine == passphrase)
    }
}
