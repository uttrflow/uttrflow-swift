// Tests the recording kept for retry and its presentation.
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// An error from outside the product's own vocabulary.
private struct OddError: Error {}

/// A dictionary that answers each read with the next list, counting the reads.
private final class WordsInTurn: Sendable {
    private let state: Mutex<(lists: [[String]], reads: Int)>

    init(_ lists: [String]...) {
        state = Mutex((lists, 0))
    }

    func next() -> [String] {
        state.withLock { state in
            state.reads += 1
            return state.lists.isEmpty ? [] : state.lists.removeFirst()
        }
    }

    var reads: Int { state.withLock { $0.reads } }
}

private let said = "hello there"

extension DictationState {
    fileprivate var failure: DictationFailure? {
        if case .failed(let failure) = self { failure } else { nil }
    }

    fileprivate var outcome: DictationOutcome? {
        if case .inserted(let outcome) = self { outcome } else { nil }
    }
}

// MARK: - Tests

/// The audio is kept exactly when the words were lost, and deleted the moment they land.
@Suite("Dictation pipeline: the recording beside the buffer")
struct DictationPipelineRecordingTests {
    private let recording = KeptRecording(id: UUID(), when: Date(), duration: .seconds(2))

    private func makePipeline(
        speech: FakeSpeechEngine = FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: said))),
        inserter: FakeTextInserter = FakeTextInserter(),
        clipboard: FakeTextInserter? = nil,
        recordings: FakeRecordingKeeper
    ) -> DictationPipeline {
        DictationPipeline(
            capture: FakeAudioCaptureEngine(),
            speech: speech,
            cleaner: FakeTranscriptCleaner(),
            context: FakeContextEngine(context: .fixture()),
            inserter: inserter,
            recordings: recordings,
            clipboard: clipboard)
    }

    private func dictate(_ pipeline: DictationPipeline) async -> DictationState {
        await pipeline.startRecording()
        await pipeline.finishRecording()
        return await pipeline.currentState
    }

    @Test("a dictation whose words landed deletes its recording")
    func successDiscards() async {
        let recordings = FakeRecordingKeeper(current: recording)
        let state = await dictate(makePipeline(recordings: recordings))

        #expect(state.outcome != nil)
        #expect(state.outcome?.isFromRecording == false)
        #expect(await recordings.discarded == [recording.id])
    }

    @Test("a dictation the recogniser lost keeps its recording and points the user at it")
    func lostWordsKeepTheRecording() async throws {
        let recordings = FakeRecordingKeeper(current: recording)
        let state = await dictate(
            makePipeline(
                speech: FakeSpeechEngine(transcribeOutcome: .failure(.transcriptionFailed(description: "x"))),
                recordings: recordings))

        let failure = try #require(state.failure)
        #expect(failure.recovery == .retryFromRecording)
        #expect(failure.transcript == nil)
        #expect(await recordings.discarded.isEmpty)
    }

    /// The capture finishes the WAV before it refuses the take, so the audio is on disk either way.
    @Test("a capture refused after the recording was written offers that recording, not the microphone")
    func refusedCaptureOffersTheRecording() async throws {
        let recordings = FakeRecordingKeeper(current: recording)
        let capture = FakeAudioCaptureEngine()
        let pipeline = DictationPipeline(
            capture: capture, speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: said))),
            cleaner: FakeTranscriptCleaner(), context: FakeContextEngine(context: .fixture()),
            inserter: FakeTextInserter(), recordings: recordings)
        await pipeline.startRecording()
        await capture.setStopOutcome(.failure(.engineFailed(description: "gone")))
        await pipeline.finishRecording()

        // Never `.retry`, which opens the microphone for a new dictation in place of the kept one.
        #expect(await pipeline.currentState.failure?.recovery == .retryFromRecording)
        #expect(await recordings.discarded.isEmpty)
    }

    /// Nothing was written, so there is nothing to offer and the failure keeps the fix it came with.
    @Test("a capture refused with no recording on disk keeps its own fix")
    func refusedCaptureWithNoRecording() async throws {
        let recordings = FakeRecordingKeeper(current: nil)
        let capture = FakeAudioCaptureEngine()
        let pipeline = DictationPipeline(
            capture: capture, speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: said))),
            cleaner: FakeTranscriptCleaner(), context: FakeContextEngine(context: .fixture()),
            inserter: FakeTextInserter(), recordings: recordings)
        await pipeline.startRecording()
        await capture.setStopOutcome(.failure(.engineFailed(description: "gone")))
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.failure?.recovery == .retry)
        #expect(await recordings.discarded.isEmpty)
    }

    @Test("a failure with its own fix keeps that fix, and the recording")
    func otherFixesAreLeftAlone() async throws {
        let recordings = FakeRecordingKeeper(current: recording)
        let state = await dictate(
            makePipeline(
                speech: FakeSpeechEngine(transcribeOutcome: .failure(.modelNotInstalled)),
                recordings: recordings))

        #expect(state.failure?.recovery == .downloadSpeechModel)
        #expect(await recordings.discarded.isEmpty)
    }

    @Test("silence has nothing worth retrying, so its recording goes")
    func silenceDiscards() async {
        let recordings = FakeRecordingKeeper(current: recording)
        let state = await dictate(
            makePipeline(
                speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: "   "))),
                recordings: recordings))

        #expect(state.failure?.severity == .informational)
        #expect(state.failure?.recovery == nil)
        #expect(await recordings.discarded == [recording.id])
    }

    @Test("words that reached the clipboard do not need the audio any more")
    func insertionFailureDiscards() async {
        let recordings = FakeRecordingKeeper(current: recording)
        let state = await dictate(
            makePipeline(
                inserter: FakeTextInserter(.failure(.noFocusedTextField)),
                recordings: recordings))

        #expect(state.failure?.transcript == said)
        #expect(state.failure?.recovery != .retryFromRecording)
        #expect(await recordings.discarded == [recording.id])
    }

    @Test("a dictation with no recording behind it fails exactly as before")
    func noRecordingChangesNothing() async {
        let recordings = FakeRecordingKeeper()
        let state = await dictate(
            makePipeline(
                speech: FakeSpeechEngine(transcribeOutcome: .failure(.transcriptionFailed(description: "x"))),
                recordings: recordings))

        #expect(state.failure?.recovery == .retry)
        #expect(await recordings.discarded.isEmpty)
    }

    @Test("cancelling after the key is released deletes the recording")
    func cancelDiscards() async {
        let recordings = FakeRecordingKeeper(current: recording)
        let pipeline = makePipeline(recordings: recordings)
        await pipeline.startRecording()
        await pipeline.finishRecording()
        await pipeline.cancel()

        #expect(await recordings.discarded == [recording.id])
    }

    // MARK: Retrying

    @Test("a retry with another engine hears the recording with it once, leaving the configured one")
    func retryWithTheOtherEngine() async throws {
        let recordings = FakeRecordingKeeper(current: recording, waiting: [recording])
        let speech = FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: "configured engine")))
        let other = FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: said)))
        let clipboard = FakeTextInserter(.success(InsertionAttempt(.clipboard)))
        let pipeline = makePipeline(speech: speech, clipboard: clipboard, recordings: recordings)

        #expect(await pipeline.retry(recording.id, hearingWith: other))
        #expect(clipboard.received == [said])
        #expect(await other.transcribeCalls.count > 0)
        #expect(await speech.transcribeCalls.isEmpty)

        _ = await dictate(pipeline)
        #expect(await speech.transcribeCalls.count > 0)
    }

    @Test("the failure names its kept recording, so one press of the notice puts the words on the clipboard")
    func noticeRetryTakesOnePress() async throws {
        let recordings = FakeRecordingKeeper(current: recording, waiting: [recording])
        let speech = FakeSpeechEngine(transcribeOutcome: .failure(.transcriptionFailed(description: "x")))
        let clipboard = FakeTextInserter(.success(InsertionAttempt(.clipboard)))
        let pipeline = makePipeline(speech: speech, clipboard: clipboard, recordings: recordings)
        let failure = try #require(await dictate(pipeline).failure)
        #expect(failure.recovery == .retryFromRecording)
        let kept = try #require(failure.keptRecording)
        #expect(kept == recording.id)

        await speech.setTranscribeOutcome(.success(.fixture(text: said)))
        #expect(await pipeline.retry(kept))

        let outcome = try #require(await pipeline.currentState.outcome)
        #expect(outcome.method == .clipboard)
        #expect(outcome.isFromRecording)
        #expect(clipboard.received == [said])
    }

    @Test("a failure that kept no recording names none")
    func noRecordingNamesNone() async throws {
        let speech = FakeSpeechEngine(transcribeOutcome: .failure(.transcriptionFailed(description: "x")))
        let pipeline = makePipeline(speech: speech, recordings: FakeRecordingKeeper())
        let failure = try #require(await dictate(pipeline).failure)
        #expect(failure.keptRecording == nil)
    }

    @Test("a retry runs the kept audio and copies the words rather than typing them")
    func retryCopies() async throws {
        let audio = AudioSamples.silence(seconds: 3)
        let recordings = FakeRecordingKeeper(waiting: [recording], audioOutcome: .success(audio))
        let speech = FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: said)))
        let inserter = FakeTextInserter()
        let clipboard = FakeTextInserter(.success(InsertionAttempt(.clipboard)))
        let pipeline = makePipeline(
            speech: speech, inserter: inserter, clipboard: clipboard, recordings: recordings)

        await pipeline.retry(recording.id)

        let outcome = try #require(await pipeline.currentState.outcome)
        #expect(outcome.text == said)
        #expect(outcome.method == .clipboard)
        #expect(outcome.isFromRecording)
        #expect(outcome.spokenFor == audio.duration)
        #expect(outcome.insertedInto == nil)
        #expect(clipboard.received == [said])
        #expect(inserter.received.isEmpty)
        #expect(await speech.transcribeCalls.last?.audio == audio)
        #expect(await recordings.audioRequests == [recording.id])
        #expect(await recordings.discarded == [recording.id])
    }

    @Test("retry cleans and recognises with the recording destination")
    func retryUsesRecordingDestination() async throws {
        let destination = AppContext(
            applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
            documentName: "private.swift", precedingText: "secret text")
        let recording = KeptRecording(
            id: UUID(), when: Date(), duration: .seconds(2), destination: destination.identity,
            fieldKind: .codeEditor)
        let recordings = FakeRecordingKeeper(waiting: [recording])
        let cleaner = FakeTranscriptCleaner()
        let speech = FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: said)))
        let words = Mutex<[AppContext]>([])
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: speech, cleaner: cleaner,
            context: FakeContextEngine(
                context: .fixture(applicationName: "Mail", bundleIdentifier: "com.apple.mail")),
            inserter: FakeTextInserter(),
            speechWords: { context in
                words.withLock { $0.append(context) }
                return ["DestinationName"]
            },
            destinationOverrides: DestinationOverrides().setting(
                .email, for: "com.apple.dt.Xcode", named: "Xcode"),
            recordings: recordings,
            clipboard: FakeTextInserter(.success(InsertionAttempt(.clipboard))))

        #expect(await pipeline.retry(recording.id))

        let request = try #require(cleaner.requests.first)
        #expect(request.context.bundleIdentifier == "com.apple.dt.Xcode")
        #expect(request.situation.destination == .codeEditor)
        #expect(words.withLock { $0.first?.bundleIdentifier } == "com.apple.dt.Xcode")
        #expect(request.context.documentName == nil)
        #expect(request.context.precedingText == nil)
    }

    /// Every attempt reads the dictionary as it is now, so a word added between attempts reaches the recogniser.
    @Test("each retry asks for the vocabulary afresh")
    func retriesReadFreshVocabulary() async {
        let words = WordsInTurn(["OldName"], ["NewName"])
        // The first retry fails, so the recording is kept for the second, as it is in the app.
        let speech = FakeSpeechEngine(transcribeOutcome: .failure(.transcriptionFailed(description: "x")))
        let recordings = FakeRecordingKeeper(waiting: [recording])
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: speech, cleaner: FakeTranscriptCleaner(),
            context: FakeContextEngine(context: .fixture()), inserter: FakeTextInserter(),
            speechWords: { _ in words.next() },
            recordings: recordings,
            clipboard: FakeTextInserter(.success(InsertionAttempt(.clipboard))))

        await pipeline.retry(recording.id)
        #expect(await recordings.discarded.isEmpty)
        await speech.setTranscribeOutcome(.success(.fixture(text: said)))
        await pipeline.retry(recording.id)

        #expect(words.reads == 2)
        #expect(await speech.transcribeCalls.events.map(\.options.vocabulary) == [["OldName"], ["NewName"]])
    }

    @Test("a retry after a dictation asks for the vocabulary afresh")
    func retryAfterDictationReadsFreshVocabulary() async {
        let words = WordsInTurn(["OldName"], ["NewName"])
        let speech = FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: said)))
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: speech, cleaner: FakeTranscriptCleaner(),
            context: FakeContextEngine(context: .fixture()), inserter: FakeTextInserter(),
            speechWords: { _ in words.next() },
            recordings: FakeRecordingKeeper(waiting: [recording]),
            clipboard: FakeTextInserter(.success(InsertionAttempt(.clipboard))))

        _ = await dictate(pipeline)
        await pipeline.retry(recording.id)

        #expect(words.reads == 2)
        #expect(await speech.transcribeCalls.events.last?.options.vocabulary == ["NewName"])
    }

    @Test("recogniser bias switched off sends the recogniser no vocabulary")
    func recogniserBiasOff() async {
        let speech = FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: said)))
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: speech, cleaner: FakeTranscriptCleaner(),
            context: FakeContextEngine(context: .fixture()), inserter: FakeTextInserter(),
            speechWords: { _ in ["Uttrflow"] },
            recordings: FakeRecordingKeeper(waiting: [recording]),
            clipboard: FakeTextInserter(.success(InsertionAttempt(.clipboard))),
            layers: QualityLayers(enabled: QualityLayers().enabled.subtracting([.recogniserBias])))

        await pipeline.retry(recording.id)

        #expect(await speech.transcribeCalls.events.map(\.options.vocabulary) == [[]])
    }

    @Test("a multi-piece dictation resolves vocabulary once and shares it with every piece")
    func dictationReadsVocabularyOnce() async {
        let words = WordsInTurn(["Uttrflow"])
        let speech = FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: said)))
        // A tone, not a constant level: loudness is measured about the frame's mean, so a DC offset is silence.
        let tone = (0..<24_000).map { 0.3 * Float(sin(Double($0) * 0.07)) }
        let audio = AudioSamples.canonical(tone + [Float](repeating: 0, count: 8_000) + tone)
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(audio))
        await capture.setCaptured(audio)
        let pipeline = DictationPipeline(
            capture: capture, speech: speech, cleaner: FakeTranscriptCleaner(),
            context: FakeContextEngine(context: .fixture()), inserter: FakeTextInserter(),
            speechWords: { _ in words.next() },
            windowing: SpeechWindowing(
                minimumLength: 1, sentencePause: 0.3, comfortableLength: 2, anyPause: 0.2,
                maximumLength: 5, minimumSpeech: 0.2))

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(words.reads == 1)
        #expect(await speech.transcribeCalls.events.count > 1)
        #expect(await speech.transcribeCalls.events.allSatisfy { $0.options.vocabulary == ["Uttrflow"] })
    }

    @Test("a retry that fails again keeps the recording for another go")
    func retryFailureKeeps() async {
        let recordings = FakeRecordingKeeper(waiting: [recording])
        let pipeline = makePipeline(
            speech: FakeSpeechEngine(transcribeOutcome: .failure(.transcriptionFailed(description: "x"))),
            recordings: recordings)

        await pipeline.retry(recording.id)

        #expect(await pipeline.currentState.failure?.recovery == .retryFromRecording)
        #expect(await recordings.discarded.isEmpty)
    }

    @Test(arguments: [
        AudioCaptureError.engineFailed(description: "gone"), .unsupportedInputFormat,
    ])
    func unreadableRecordingIsDroppedWithoutOfferingRetry(_ error: AudioCaptureError) async {
        let recordings = FakeRecordingKeeper(waiting: [recording], audioOutcome: .failure(error))
        let pipeline = makePipeline(recordings: recordings)

        await pipeline.retry(recording.id)

        let failure = await pipeline.currentState.failure
        #expect(failure?.message == "That recording couldn't be read, so it can't be retried.")
        #expect(failure?.recovery == nil)
        #expect(failure?.severity != .blocking)
        #expect(await recordings.discarded == [recording.id])
    }

    @Test("a retry waits its turn behind a dictation under way")
    func retryRefusedWhileBusy() async {
        let recordings = FakeRecordingKeeper(waiting: [recording])
        let pipeline = makePipeline(recordings: recordings)
        await pipeline.startRecording()

        await pipeline.retry(recording.id)

        #expect(await pipeline.currentState == .recording)
        #expect(await recordings.audioRequests.isEmpty)
    }

    @Test("the pipeline keeps nothing when it was given nowhere to keep it")
    func defaultKeeperKeepsNothing() async {
        let keeper = RecordingsNotKept()
        #expect(await keeper.current() == nil)
        #expect(await keeper.waiting(now: Date()).isEmpty)
        await keeper.discard(UUID())
        await #expect(throws: AudioCaptureError.self) { _ = try await keeper.audio(of: UUID()) }
    }

    @Test("the fake keeper refuses audio for an ID it never kept")
    func fakeKeeperRejectsUnknownID() async {
        let recordings = FakeRecordingKeeper(waiting: [recording])
        await #expect(throws: AudioCaptureError.self) { _ = try await recordings.audio(of: UUID()) }
    }

    @Test("the fake keeper refuses audio for an ID it discarded")
    func fakeKeeperRejectsDiscardedID() async {
        let recordings = FakeRecordingKeeper(waiting: [recording])
        await recordings.discard(recording.id)
        await #expect(throws: AudioCaptureError.self) { _ = try await recordings.audio(of: recording.id) }
    }

    @Test("a retry after the recording is gone follows the failure path")
    func retryAfterMissingRecordingFails() async {
        let recordings = FakeRecordingKeeper()
        let pipeline = makePipeline(recordings: recordings)

        await pipeline.retry(recording.id)

        #expect(await pipeline.currentState.failure != nil)
        #expect(await recordings.discarded == [recording.id])
    }
}

/// The state that exists so a tick cannot be shown before the words are on screen.
@Suite("Inserting, which is still working as far as the user is concerned")
struct InsertingStateTests {
    @Test("reads as work in progress rather than a result")
    func showsProgress() {
        let dock = DictationPresenter.dock(for: .inserting(into: nil))

        #expect(dock.showsProgress)
        #expect(dock.showsWaveform == false)
        #expect(dock.symbolName != "checkmark", "a tick here is the bug this state exists to fix")
        #expect(dock.secondaryLine == nil, "nothing to preview until the words have landed")
    }

    @Test("holds the dictation open, so a second one cannot start over it")
    func staysBusy() {
        #expect(DictationState.inserting(into: nil).isBusy)
        #expect(DictationState.inserting(into: nil).isListening == false)
    }

    /// One wait to the person waiting, so a second wording would only announce our own plumbing.
    @Test("says exactly what tidying says, because it is the same wait")
    func speaksWithOneVoice() {
        let inserting = DictationPresenter.dock(for: .inserting(into: nil))
        let tidying = DictationPresenter.dock(for: .tidying)

        #expect(inserting == tidying)
        #expect(inserting.accessibilityLabel.lowercased().contains("paste") == false)
    }
}

/// The floating button, for a dictation that came from a recording.
@Suite("Failure presentation for a retried dictation")
struct RetriedDictationPresentationTests {
    @Test("a retried dictation says it was copied, without blaming Accessibility")
    func copiedOnPurpose() {
        let outcome = DictationOutcome(
            text: "Hello there.", method: .clipboard, cleanedBy: .rules, fromRecording: true)
        let dock = DictationPresenter.dock(for: .inserted(outcome))
        #expect(dock.primaryLine == "Copied — press ⌘V")
        #expect(dock.action == nil)
        #expect(dock.accessibilityLabel.contains("Hello there."))
        #expect(!dock.accessibilityLabel.contains("Accessibility"))
    }

    @Test("a live dictation that fell to the clipboard still points at Accessibility")
    func copiedForWantOfAccessibility() {
        let outcome = DictationOutcome(text: "Hello there.", method: .clipboard, cleanedBy: .rules)
        let dock = DictationPresenter.dock(for: .inserted(outcome))
        #expect(dock.action == .openSystemSettings(.accessibility))
    }

    @Test("a failure can be re-offered with a different next step")
    func offering() {
        let failure = DictationFailure(message: "Lost it.", recovery: .retry, severity: .recoverable)
        let offered = failure.offering(.retryFromRecording)
        #expect(offered.recovery == .retryFromRecording)
        #expect(offered.message == "Lost it. Your recording is kept on this Mac.")
        #expect(offered.severity == failure.severity)
    }
}

@Suite("The fake audio capture engine follows the real engine's lifecycle contract")
struct FakeAudioCaptureEngineTests {
    @Test("stop while idle throws notRecording, and idle is unchanged")
    func idleStopThrows() async {
        let capture = FakeAudioCaptureEngine()
        await #expect(throws: AudioCaptureError.notRecording) { _ = try await capture.stop() }
        #expect(await capture.state == .idle)
    }

    @Test("a second start while recording throws alreadyRecording")
    func repeatedStartThrows() async throws {
        let capture = FakeAudioCaptureEngine()
        try await capture.start()
        await #expect(throws: AudioCaptureError.alreadyRecording) { try await capture.start() }
        #expect(await capture.state == .recording)
    }

    @Test("a scripted stop failure still leaves the engine idle")
    func failedStopGoesIdle() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .failure(.engineFailed(description: "gone")))
        try await capture.start()
        await #expect(throws: AudioCaptureError.self) { _ = try await capture.stop() }
        #expect(await capture.state == .idle)
    }
}
