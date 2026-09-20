// Tests that a stage which never returns is timed out.
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A ``SpeechEngine`` that accepts the audio and never answers.
private actor NeverAnsweringSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        // Suspends for ever, the way a wedged decoder does. Nothing resumes this.
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
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
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        return TransformationResult(text: request.transcription.text, producedBy: .rules)
    }
}

/// A ``TextInserting`` that takes the text and never answers, the way a hung application does.
private struct NeverAnsweringInserter: TextInserting {
    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        return InsertionAttempt(.accessibility)
    }
}

@Suite("Dictation pipeline: a stage that never answers", .timeLimit(.minutes(1)))
struct DictationStageTimeoutTests {
    /// Reaches `stage`, then fires its own timer once it is set, never advancing after the stage has ended.
    private func expire(
        _ limit: Duration, at stage: DictationState, of pipeline: DictationPipeline,
        on clock: ManualClock
    ) async {
        while !Task.isCancelled, await pipeline.currentState != stage { await Task.yield() }
        while !Task.isCancelled, await pipeline.currentState == stage {
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

        guard case .failed = await pipeline.currentState else {
            Issue.record("expected the dictation to fail, got \(await pipeline.currentState)")
            return
        }
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
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: FakeSpeechEngine(
                transcribeOutcome: .success(Transcription(text: "what I said"))),
            cleaner: NeverAnsweringCleaner(),
            context: FakeContextEngine(),
            inserter: inserter,
            metrics: metrics,
            clock: clock)

        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await expire(StageTimeout.transformation, at: .tidying, of: pipeline, on: clock)
        await settle(finishing)

        // Untidied but inserted: §19 says tidying's failure never costs the words.
        #expect(inserter.inserted == ["what I said"])
        guard case .inserted = await pipeline.currentState else {
            Issue.record("expected the words to land, got \(await pipeline.currentState)")
            return
        }
        // The words still landed, and the tidying is still counted as the failure it was.
        #expect(await metrics.measurements(for: .transformation).map(\.succeeded) == [false])
        #expect(await metrics.measurements(for: .insertion).map(\.succeeded) == [true])
    }

    @Test("an application that never takes the words fails the dictation and counts the insertion failed")
    func insertionThatNeverAnswers() async {
        let clock = ManualClock()
        let metrics = RecordingMetricsRecorder()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: FakeSpeechEngine(
                transcribeOutcome: .success(Transcription(text: "what I said"))),
            cleaner: TimeoutTestCleaner(),
            context: FakeContextEngine(),
            inserter: NeverAnsweringInserter(),
            metrics: metrics,
            clock: clock)

        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await expire(StageTimeout.quick, at: .inserting, of: pipeline, on: clock)
        await settle(finishing)

        guard case .failed(let failure) = await pipeline.currentState else {
            Issue.record("expected the dictation to fail, got \(await pipeline.currentState)")
            return
        }
        #expect(failure.transcript == "Tidied.")
        #expect(await metrics.measurements(for: .insertion).map(\.succeeded) == [false])
        #expect(await metrics.measurements(for: .transcription).map(\.succeeded) == [true])
    }
}
