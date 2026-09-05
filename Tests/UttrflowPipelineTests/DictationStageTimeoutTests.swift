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

    func insert(_ text: String) async throws(TextInsertionError) -> TextInsertionMethod {
        placed.withLock { $0.append(text) }
        return .accessibility
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

@Suite("Dictation pipeline: a stage that never answers")
struct DictationStageTimeoutTests {
    /// Reaches `stage` and advances until it is left, since an earlier deadline may still be installed.
    private func expire(
        _ limit: Duration, at stage: DictationState, of pipeline: DictationPipeline,
        on clock: ManualClock
    ) async {
        while await pipeline.currentState != stage { await Task.yield() }
        while await pipeline.currentState == stage {
            await clock.advanceWhenSomethingIsWaiting(by: limit)
            await Task.yield()
        }
    }

    @Test("a recogniser that never answers ends the dictation instead of wedging it")
    func transcriptionThatNeverAnswers() async {
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
        await finishing.value

        guard case .failed = await pipeline.currentState else {
            Issue.record("expected the dictation to fail, got \(await pipeline.currentState)")
            return
        }
        // The point of the whole thing: not busy, so the next dictation can start.
        #expect(await pipeline.currentState.isBusy == false)
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
        await finishing.value

        await pipeline.startRecording()
        #expect(await pipeline.currentState == .recording)
    }

    @Test("a tidier that never answers costs the tidying, never the words")
    func tidyingThatNeverAnswers() async {
        let clock = ManualClock()
        let inserter = TimeoutTestInserter()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: FakeSpeechEngine(
                transcribeOutcome: .success(Transcription(text: "what I said"))),
            cleaner: NeverAnsweringCleaner(),
            context: FakeContextEngine(),
            inserter: inserter,
            clock: clock)

        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await expire(StageTimeout.transformation, at: .tidying, of: pipeline, on: clock)
        await finishing.value

        // Untidied but inserted: §19 says tidying's failure never costs the words.
        #expect(inserter.inserted == ["what I said"])
        guard case .inserted = await pipeline.currentState else {
            Issue.record("expected the words to land, got \(await pipeline.currentState)")
            return
        }
    }
}
