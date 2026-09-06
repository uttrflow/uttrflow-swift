// Tests the recording kept for retry and its presentation.
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// A ``TranscriptCleaning`` that hands the words back untouched.
private struct RecordingFakeCleaner: TranscriptCleaning {
    func clean(_ request: TransformationRequest) async throws(TransformationError) -> TransformationResult {
        TransformationResult(text: request.transcription.text, producedBy: .rules)
    }
}

/// A ``TextInserting`` that records what it is handed and answers as scripted.
private final class RecordingFakeInserter: TextInserting, Sendable {
    private struct State: Sendable {
        var outcome: ScriptedOutcome<TextInsertionMethod, TextInsertionError>
        var received: [String] = []
    }

    private let state: Mutex<State>

    init(outcome: ScriptedOutcome<TextInsertionMethod, TextInsertionError> = .success(.accessibility)) {
        state = Mutex(State(outcome: outcome))
    }

    func insert(_ text: String) async throws(TextInsertionError) -> TextInsertionMethod {
        let outcome = state.withLock { state -> ScriptedOutcome<TextInsertionMethod, TextInsertionError> in
            state.received.append(text)
            return state.outcome
        }
        return try outcome.resolve()
    }

    var received: [String] { state.withLock { $0.received } }
}

/// An error from outside the product's own vocabulary.
private struct OddError: Error {}

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
        inserter: RecordingFakeInserter = RecordingFakeInserter(),
        clipboard: RecordingFakeInserter? = nil,
        recordings: FakeRecordingKeeper
    ) -> DictationPipeline {
        DictationPipeline(
            capture: FakeAudioCaptureEngine(),
            speech: speech,
            cleaner: RecordingFakeCleaner(),
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

    @Test("an error nobody foresaw also leaves the recording to retry")
    func unforeseenErrorKeepsTheRecording() async throws {
        let recordings = FakeRecordingKeeper(current: recording)
        let capture = FakeAudioCaptureEngine()
        let pipeline = DictationPipeline(
            capture: capture, speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: said))),
            cleaner: RecordingFakeCleaner(), context: FakeContextEngine(context: .fixture()),
            inserter: RecordingFakeInserter(), recordings: recordings)
        await pipeline.startRecording()
        await capture.setStopOutcome(.failure(.engineFailed(description: "gone")))
        await pipeline.finishRecording()

        // The microphone never stopped cleanly, so there was no recording to reason about.
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
                inserter: RecordingFakeInserter(outcome: .failure(.noFocusedTextField)),
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

    @Test("a retry runs the kept audio and copies the words rather than typing them")
    func retryCopies() async throws {
        let audio = AudioSamples.silence(seconds: 3)
        let recordings = FakeRecordingKeeper(waiting: [recording], audioOutcome: .success(audio))
        let speech = FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: said)))
        let inserter = RecordingFakeInserter()
        let clipboard = RecordingFakeInserter(outcome: .success(.clipboard))
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

    @Test("a recording that cannot be read is not offered again")
    func unreadableRecordingIsDropped() async {
        let recordings = FakeRecordingKeeper(
            waiting: [recording], audioOutcome: .failure(.engineFailed(description: "gone")))
        let pipeline = makePipeline(recordings: recordings)

        await pipeline.retry(recording.id)

        #expect(await pipeline.currentState.failure != nil)
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
}

/// The state that exists so a tick cannot be shown before the words are on screen.
@Suite("Inserting, which is still working as far as the user is concerned")
struct InsertingStateTests {
    @Test("reads as work in progress rather than a result")
    func showsProgress() {
        let dock = DictationPresenter.dock(for: .inserting)

        #expect(dock.showsProgress)
        #expect(dock.showsWaveform == false)
        #expect(dock.symbolName != "checkmark", "a tick here is the bug this state exists to fix")
        #expect(dock.secondaryLine == nil, "nothing to preview until the words have landed")
    }

    @Test("holds the dictation open, so a second one cannot start over it")
    func staysBusy() {
        #expect(DictationState.inserting.isBusy)
        #expect(DictationState.inserting.isListening == false)
    }

    /// One wait to the person waiting, so a second wording would only announce our own plumbing.
    @Test("says exactly what tidying says, because it is the same wait")
    func speaksWithOneVoice() {
        let inserting = DictationPresenter.dock(for: .inserting)
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
        #expect(offered.message == failure.message)
        #expect(offered.severity == failure.severity)
    }
}
