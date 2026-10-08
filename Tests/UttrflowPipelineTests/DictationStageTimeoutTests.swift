// Tests that a stage which never returns is timed out.
import Synchronization
import Testing
import UttrflowInput
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.UUID

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

private func suspendUntilCancelled() async {
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3600))
    }
}

/// A ``SpeechEngine`` that accepts the audio and never answers.
private actor NeverAnsweringSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        // Suspends for ever, the way a wedged decoder does. Nothing resumes this.
        await suspendUntilCancelled()
        return .fixture()
    }
}

/// A ``TranscriptCleaning`` that tidies, so a test can watch a different stage.
private struct TimeoutTestCleaner: TranscriptCleaning {
    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        TransformationResult(text: "Tidied.", producedBy: .rules)
    }
}

/// Keeps every account the pipeline hands on, so a stage that gave up can be seen in it.
private actor TimeoutCleaningRecorder: CleaningRecording {
    private(set) var records: [CleaningRecord] = []

    func record(_ record: CleaningRecord) async { records.append(record) }
}

/// A ``TextInserting`` that records what reached the screen.
private final class TimeoutTestInserter: TextInserting, Sendable {
    private let placed = Mutex<[String]>([])

    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        placed.withLock { $0.append(text) }
        return InsertionAttempt(.accessibility)
    }

    var inserted: [String] { placed.withLock { $0 } }
}

/// A ``TranscriptCleaning`` that accepts the text and never answers.
private struct NeverAnsweringCleaner: TranscriptCleaning {
    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        await suspendUntilCancelled()
        return TransformationResult(text: request.transcription.text, producedBy: .rules)
    }
}

/// The first insertion strategy never returns, so the clipboard fallback cannot start.
private struct NeverAnsweringEngine: TextInsertionEngine {
    let method: TextInsertionMethod = .accessibility

    func canInsert() async -> Bool { true }

    func insert(_ text: String) async throws(TextInsertionError) -> InsertionArrival {
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        return .notReported
    }
}

/// A ``TextInserting`` that takes the text and never answers, the way a hung application does.
private struct NeverAnsweringInserter: TextInserting {
    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        await suspendUntilCancelled()
        return InsertionAttempt(.accessibility)
    }
}

private actor NeverAnsweringCapture: AudioCaptureEngine {
    enum Event: Sendable, Equatable {
        case start
        case stop
    }

    private var currentState: AudioCaptureState = .idle
    let calls = CallLog<Event>()

    var state: AudioCaptureState { currentState }

    func start() async throws(AudioCaptureError) {
        await calls.append(.start)
        currentState = .recording
    }

    func stop() async throws(AudioCaptureError) -> AudioSamples {
        await calls.append(.stop)
        await suspendUntilCancelled()
        currentState = .idle
        return .silence(seconds: 2)
    }

    func cancel() async {
        currentState = .idle
    }
}

private actor NeverAnsweringContextEngine: ContextEngine {
    let calls = CallLog<Void>()

    func currentContext() async -> AppContext {
        await calls.append(())
        await suspendUntilCancelled()
        return .unknown
    }
}

private struct NeverAnsweringCorrector: WordCorrecting {
    let calls = CallLog<Void>()

    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> [DictationCorrection] {
        await calls.append(())
        await suspendUntilCancelled()
        return []
    }
}

private struct NeverAnsweringExpander: SnippetExpanding {
    let calls = CallLog<Void>()

    func expand(_ text: String) async throws(DictationChangeError) -> ExpandedTranscript {
        await calls.append(())
        await suspendUntilCancelled()
        return .unchanged(text)
    }
}

/// A ``TextInserting`` that never confirms a copy.
private struct NeverAnsweringClipboard: TextInserting {
    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        await suspendUntilCancelled()
        return InsertionAttempt(.clipboard)
    }
}

private final class TimeoutPasteboard: Pasteboard, Sendable {
    private let stored = Mutex<String?>("older copied text")

    func text() -> String? { stored.withLock { $0 } }
    func setText(_ text: String) -> PasteboardWriteResult {
        stored.withLock { $0 = text }
        return .written(changeCount: nil)
    }
    func setConcealedText(_ text: String) -> PasteboardWriteResult { setText(text) }
    func setImage(_ data: Data) -> PasteboardWriteResult {
        stored.withLock { $0 = nil }
        return .written(changeCount: nil)
    }
}

@Suite("Dictation pipeline: a stage that never answers", .timeLimit(.minutes(1)))
struct DictationStageTimeoutTests {
    /// Reaches `stage`, then fires its own timer once it is set, never advancing after the stage has ended.
    private func expire(
        _ limit: Duration, at stage: DictationState, of pipeline: DictationPipeline,
        on clock: ManualClock
    ) async {
        while !Task.isCancelled, !(await pipeline.currentState).isStage(of: stage) { await Task.yield() }
        while !Task.isCancelled, (await pipeline.currentState).isStage(of: stage) {
            if clock.advanceIfSomethingIsWaiting(exactly: limit) { return }
            await Task.yield()
        }
    }

    /// Waits for `finishing`, or stops waiting once the test is cancelled, so the time limit can end a wedged run.
    private func settle(_ finishing: Task<Void, Never>) async {
        let waiting = Mutex<(continuation: CheckedContinuation<Void, Never>?, done: Bool)>((nil, false))
        let wake: @Sendable () -> Void = {
            waiting.withLock { state -> CheckedContinuation<Void, Never>? in
                state.done = true
                defer { state.continuation = nil }
                return state.continuation
            }?.resume()
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let parked = waiting.withLock { state -> Bool in
                    guard !state.done, !Task.isCancelled else { return false }
                    state.continuation = continuation
                    return true
                }
                guard parked else { return continuation.resume() }
                Task {
                    await finishing.value
                    wake()
                }
            }
        } onCancel: {
            wake()
        }
    }

    private func waitForCall(_ calls: CallLog<Void>) async {
        while !Task.isCancelled, await calls.count == 0 { await Task.yield() }
    }

    @Test("a recogniser that never answers ends the dictation instead of wedging it")
    func transcriptionThatNeverAnswers() async {
        let clock = ManualClock()
        let metrics = RecordingMetricsRecorder()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: NeverAnsweringSpeechEngine(),
            cleaner: TimeoutTestCleaner(),
            context: FakeContextEngine(),
            inserter: TimeoutTestInserter(),
            metrics: metrics,
            clock: clock)

        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await expire(StageTimeout.transcription, at: .transcribing, of: pipeline, on: clock)
        await settle(finishing)

        guard case .failed(let failure) = await pipeline.currentState else {
            Issue.record("expected the dictation to fail, got \(await pipeline.currentState)")
            return
        }
        // A hang is told apart from a fault, since its remedy is to wait or free the Mac.
        #expect(failure.speechEngineError == .recogniserTimedOut)
        // The point of the whole thing: not busy, so the next dictation can start.
        #expect(await pipeline.currentState.isBusy == false)
        // An expired stage is a failed one, or the failure counts never see a hung recogniser.
        #expect(await metrics.measurements(for: .transcription).map(\.succeeded) == [false])
    }

    @Test("a dictation can begin again after a stage timed out")
    func recoversForTheNextDictation() async {
        let clock = ManualClock()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: NeverAnsweringSpeechEngine(),
            cleaner: TimeoutTestCleaner(),
            context: FakeContextEngine(),
            inserter: TimeoutTestInserter(),
            clock: clock)

        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await expire(StageTimeout.transcription, at: .transcribing, of: pipeline, on: clock)
        await settle(finishing)

        await pipeline.startRecording()
        #expect(await pipeline.currentState == .recording)
    }

    @Test("a tidier that never answers costs the tidying, never the words")
    func tidyingThatNeverAnswers() async {
        let clock = ManualClock()
        let metrics = RecordingMetricsRecorder()
        let inserter = TimeoutTestInserter()
        let recorder = TimeoutCleaningRecorder()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: FakeSpeechEngine(
                transcribeOutcome: .success(Transcription(text: "what I said"))),
            cleaner: NeverAnsweringCleaner(),
            context: FakeContextEngine(),
            inserter: inserter,
            metrics: metrics,
            cleaningRecorder: recorder,
            clock: clock)

        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await expire(StageTimeout.transformation, at: .tidying, of: pipeline, on: clock)
        await settle(finishing)

        // Untidied but inserted: §19 says tidying's failure never costs the words.
        #expect(inserter.inserted == ["what I said"])
        guard case .inserted(let outcome) = await pipeline.currentState else {
            Issue.record("expected the words to land, got \(await pipeline.currentState)")
            return
        }
        #expect(outcome.text == "what I said")
        #expect(outcome.cleanedBy == .untidied)
        // The words still landed, and the tidying is still counted as the failure it was.
        #expect(await metrics.measurements(for: .transformation).map(\.succeeded) == [false])
        #expect(await metrics.measurements(for: .insertion).map(\.succeeded) == [true])
        #expect(await recorder.records.map(\.skippedStages) == [[.init(.tidy, .timeout)]])
        // The wait after release ran past its target, and the timed-out tidy is named as why.
        #expect(outcome.slowCause == .tidyTimeout)
        #expect(await metrics.waits.map(\.cause) == [.tidyTimeout])
    }

    @Test("an application that never takes the words fails the dictation and counts the insertion failed")
    func insertionThatNeverAnswers() async {
        let clock = ManualClock()
        let metrics = RecordingMetricsRecorder()
        let pasteboard = TimeoutPasteboard()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: FakeSpeechEngine(
                transcribeOutcome: .success(Transcription(text: "what I said"))),
            cleaner: TimeoutTestCleaner(),
            context: FakeContextEngine(),
            inserter: TextInsertionCoordinator(strategies: [
                NeverAnsweringEngine(), ClipboardTextInsertionEngine(pasteboard: pasteboard),
            ]),
            metrics: metrics,
            clock: clock)

        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await expire(StageTimeout.insertion, at: .inserting(into: nil), of: pipeline, on: clock)
        await settle(finishing)

        guard case .failed(let failure) = await pipeline.currentState else {
            Issue.record("expected the dictation to fail, got \(await pipeline.currentState)")
            return
        }
        #expect(failure.transcript == "Tidied.")
        #expect(failure.recovery == .showHistory)
        #expect(failure.message.contains("History"))
        #expect(!failure.message.contains("copied"))
        #expect(!failure.message.contains("⌘V"))
        #expect(pasteboard.text() == "older copied text")
        #expect(await metrics.measurements(for: .insertion).map(\.succeeded) == [false])
        #expect(await metrics.measurements(for: .transcription).map(\.succeeded) == [true])

        // A hung application must not take the next dictation down with the one it never answered.
        await pipeline.startRecording()
        #expect(await pipeline.currentState == .recording)
    }

    @Test("a copy that never answers reports a clipboard failure, not an application timeout")
    func copyThatNeverAnswers() async {
        let clock = ManualClock()
        let recording = KeptRecording(id: UUID(), when: Date(), duration: .seconds(2))
        let recordings = FakeRecordingKeeper(
            waiting: [recording], audioOutcome: .success(.silence(seconds: 2)))
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(),
            speech: FakeSpeechEngine(
                transcribeOutcome: .success(Transcription(text: "what I said"))),
            cleaner: TimeoutTestCleaner(),
            context: FakeContextEngine(),
            inserter: TimeoutTestInserter(),
            recordings: recordings,
            clipboard: NeverAnsweringClipboard(),
            clock: clock)

        let retrying = Task { _ = await pipeline.retry(recording.id) }
        await expire(StageTimeout.insertion, at: .inserting(into: nil), of: pipeline, on: clock)
        await settle(retrying)

        guard case .failed(let failure) = await pipeline.currentState else {
            Issue.record("expected the copy to fail, got \(await pipeline.currentState)")
            return
        }
        #expect(failure.message == TextInsertionError.clipboardUnavailable.userMessage)
        #expect(failure.recovery == .showHistory)
    }

    /// The words are the only thing left when the application will not take them, so the failure carries them.
    @Test("the words a hung application never took are still offered, untidied or not")
    func insertionTimeoutKeepsTheWords() async {
        let clock = ManualClock()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: FakeSpeechEngine(
                transcribeOutcome: .success(Transcription(text: "what I said"))),
            cleaner: NeverAnsweringCleaner(),
            context: FakeContextEngine(),
            inserter: NeverAnsweringInserter(),
            clock: clock)

        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await expire(StageTimeout.transformation, at: .tidying, of: pipeline, on: clock)
        await expire(StageTimeout.insertion, at: .inserting(into: nil), of: pipeline, on: clock)
        await settle(finishing)

        guard case .failed(let failure) = await pipeline.currentState else {
            Issue.record("expected the dictation to fail, got \(await pipeline.currentState)")
            return
        }
        // Tidying timed out too, so what is offered is what the recogniser heard.
        #expect(failure.transcript == "what I said")
        #expect(await pipeline.currentState.isBusy == false)
    }

    @Test("a microphone stop that never answers fails with a retry and releases the next dictation")
    func microphoneStopThatNeverAnswers() async {
        let clock = ManualClock()
        let capture = NeverAnsweringCapture()
        let pipeline = DictationPipeline(
            capture: capture,
            speech: FakeSpeechEngine(),
            cleaner: TimeoutTestCleaner(),
            context: FakeContextEngine(),
            inserter: TimeoutTestInserter(),
            clock: clock)

        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        while !(await capture.calls.contains(.stop)) { await Task.yield() }
        await expire(StageTimeout.captureStop, at: .recording, of: pipeline, on: clock)
        await settle(finishing)

        guard case .failed(let failure) = await pipeline.currentState else {
            Issue.record("expected the microphone timeout to fail, got \(await pipeline.currentState)")
            return
        }
        #expect(failure.message == "Recording stopped unexpectedly. Try again.")
        #expect(failure.recovery == .retry)
        #expect(failure.transcript == nil)

        await pipeline.startRecording()
        #expect(await pipeline.currentState == .recording)
    }

    @Test("a screen read that never answers uses the unknown context and keeps the dictation")
    func screenReadThatNeverAnswers() async {
        let clock = ManualClock()
        let context = NeverAnsweringContextEngine()
        let inserter = TimeoutTestInserter()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: FakeSpeechEngine(
                transcribeOutcome: .success(Transcription(text: "what I said"))),
            cleaner: TimeoutTestCleaner(),
            context: context,
            inserter: inserter,
            clock: clock)

        await pipeline.startRecording()
        await waitForCall(context.calls)
        await expire(StageTimeout.screenRead, at: .recording, of: pipeline, on: clock)
        // Every later read of the same hung screen runs out too, or the finish waits on a clock nobody moves.
        let finishing = Task { await pipeline.finishRecording() }
        let finished = Mutex(false)
        let watching = Task {
            await finishing.value
            finished.withLock { $0 = true }
        }
        while !Task.isCancelled, !finished.withLock({ $0 }) {
            clock.advanceIfSomethingIsWaiting(exactly: StageTimeout.screenRead)
            await Task.yield()
        }
        await settle(watching)

        #expect(inserter.inserted == ["Tidied."])
        guard case .inserted(let outcome) = await pipeline.currentState else {
            Issue.record("expected the dictation to insert, got \(await pipeline.currentState)")
            return
        }
        #expect(outcome.insertedInto == nil)

        await pipeline.startRecording()
        #expect(await pipeline.currentState == .recording)
    }

    @Test("once a screen read times out, later reads in the dictation skip instead of waiting again")
    func stuckScreenReadSpendsTheBudgetOnce() async {
        let clock = ManualClock()
        let context = NeverAnsweringContextEngine()
        let inserter = TimeoutTestInserter()
        let metrics = RecordingMetricsRecorder()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: FakeSpeechEngine(
                transcribeOutcome: .success(Transcription(text: "what I said"))),
            cleaner: TimeoutTestCleaner(),
            context: context,
            inserter: inserter,
            metrics: metrics,
            clock: clock)

        await pipeline.startRecording()
        await waitForCall(context.calls)
        await expire(StageTimeout.screenRead, at: .recording, of: pipeline, on: clock)
        // The test moves the clock once; a later read waiting on its own limit would hang until the time limit.
        await settle(Task { await pipeline.finishRecording() })

        #expect(inserter.inserted == ["Tidied."])
        #expect(await context.calls.count == 1)
        let spent = await metrics.screenReads.map(\.duration).reduce(.zero, +)
        #expect(spent <= StageTimeout.screenRead)
    }

    @Test("a dictionary lookup that never answers skips correction and keeps the tidied words")
    func dictionaryLookupThatNeverAnswers() async {
        let clock = ManualClock()
        let corrector = NeverAnsweringCorrector()
        let inserter = TimeoutTestInserter()
        let recorder = TimeoutCleaningRecorder()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: FakeSpeechEngine(
                transcribeOutcome: .success(Transcription(text: "what I said"))),
            cleaner: TimeoutTestCleaner(),
            context: FakeContextEngine(),
            inserter: inserter,
            corrector: corrector,
            cleaningRecorder: recorder,
            clock: clock)

        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await waitForCall(corrector.calls)
        await expire(StageTimeout.correction, at: .tidying, of: pipeline, on: clock)
        await settle(finishing)

        #expect(inserter.inserted == ["Tidied."])
        // The words are as before; only the account says the dictionary gave up.
        #expect(await recorder.records.map(\.skippedStages) == [[.init(.correction, .timeout)]])
        guard case .inserted = await pipeline.currentState else {
            Issue.record("expected the dictation to insert, got \(await pipeline.currentState)")
            return
        }

        await pipeline.startRecording()
        #expect(await pipeline.currentState == .recording)
    }

    @Test("a snippet expansion that never answers inserts the tidied words unchanged")
    func snippetExpansionThatNeverAnswers() async {
        let clock = ManualClock()
        let snippets = NeverAnsweringExpander()
        let inserter = TimeoutTestInserter()
        let recorder = TimeoutCleaningRecorder()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: FakeSpeechEngine(
                transcribeOutcome: .success(Transcription(text: "what I said"))),
            cleaner: TimeoutTestCleaner(),
            context: FakeContextEngine(),
            inserter: inserter,
            snippets: snippets,
            cleaningRecorder: recorder,
            clock: clock)

        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await waitForCall(snippets.calls)
        await expire(StageTimeout.expansion, at: .tidying, of: pipeline, on: clock)
        await settle(finishing)

        #expect(inserter.inserted == ["Tidied."])
        #expect(await recorder.records.map(\.skippedStages) == [[.init(.expansion, .timeout)]])
        guard case .inserted = await pipeline.currentState else {
            Issue.record("expected the dictation to insert, got \(await pipeline.currentState)")
            return
        }

        await pipeline.startRecording()
        #expect(await pipeline.currentState == .recording)
    }
}

extension DictationState {
    /// The same stage, whichever app an insertion names.
    func isStage(of other: DictationState) -> Bool {
        if case .inserting = self, case .inserting = other { return true }
        return self == other
    }
}
