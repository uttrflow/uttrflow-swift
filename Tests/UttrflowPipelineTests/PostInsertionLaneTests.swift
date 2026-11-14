// Tests that work queued after an insertion stays off the dictation's own path.
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A vocabulary store that does not answer until the test lets it, as a slow disk would.
private final class HeldVocabulary: VocabularyLearning, Sendable {
    private let release = AsyncStream<Void>.makeStream()
    private let state = Mutex((entered: 0, learned: 0))

    /// How many lessons have begun, answered or not.
    var entered: Int { state.withLock { $0.entered } }

    var count: Int { state.withLock { $0.learned } }

    func open() { release.continuation.yield() }

    func learn(
        heard: String, wrote: String, seeing context: AppContext
    ) async throws(DictationChangeError) {
        state.withLock { $0.entered += 1 }
        for await _ in release.stream { break }
        state.withLock { $0.learned += 1 }
    }
}

private func makePipeline(vocabulary: any VocabularyLearning) -> DictationPipeline {
    DictationPipeline(
        capture: FakeAudioCaptureEngine(),
        speech: FakeSpeechEngine(
            transcribeOutcome: .success(.fixture(text: "open the payment sheet and send my address"))),
        cleaner: FakeTranscriptCleaner(producedBy: .foundationModels),
        context: FakeContextEngine(context: .fixture()),
        inserter: FakeTextInserter(),
        vocabulary: vocabulary,
        metrics: RecordingMetricsRecorder(),
        clock: ManualClock())
}

@Suite("Work after the words land stays off the dictation's own path")
struct PostInsertionLaneTests {
    @Test("a slow learner does not hold the dictation, and still learns once released")
    func slowLearnerDoesNotHoldTheDictation() async {
        let vocabulary = HeldVocabulary()
        let pipeline = makePipeline(vocabulary: vocabulary)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        guard case .inserted = await pipeline.currentState else {
            Issue.record("the dictation did not finish while the learner was held")
            return
        }
        #expect(vocabulary.count == 0)

        vocabulary.open()
        await pipeline.settlePostInsertion()
        #expect(vocabulary.count == 1)
    }

    @Test("a second dictation starts while the first one's learner is held mid-answer")
    func nextDictationStartsWhileHeld() async {
        let vocabulary = HeldVocabulary()
        let pipeline = makePipeline(vocabulary: vocabulary)

        await pipeline.startRecording()
        await pipeline.finishRecording()
        while !Task.isCancelled, vocabulary.entered == 0 { await Task.yield() }

        await pipeline.startRecording()
        await pipeline.finishRecording()
        #expect(vocabulary.count == 0)
        #expect(vocabulary.entered == 1)

        vocabulary.open()
        vocabulary.open()
        await pipeline.settlePostInsertion()
        #expect(vocabulary.count == 2)
    }
}

extension DictationPipeline {
    /// Ends the recording and waits for the learning and counting its insertion queued.
    func finishRecordingAndSettle() async {
        await finishRecording()
        await settlePostInsertion()
    }
}
