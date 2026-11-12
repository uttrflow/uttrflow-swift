import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("An unconfirmed paste outdates the next dictation's first caret read", .timeLimit(.minutes(1)))
struct PendingPasteContextTests {
    @Test("An immediately returned stale caret is retried before the second dictation finishes")
    func staleCaretIsRetriedBeforeKeyUp() async throws {
        let context = PendingPasteContext()
        let inserter = FakeTextInserter(.success(InsertionAttempt(.pasteboard, arrival: .unconfirmed)))
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(),
            speech: FakeSpeechEngine(
                transcribing: .successes([
                    .fixture(text: "we moved the review"), .fixture(text: "to the next slot"),
                ])),
            cleaner: FakeTranscriptCleaner(producedBy: .foundationModels),
            context: context, inserter: inserter)

        await pipeline.startRecording()
        await pipeline.finishRecording()
        let settled = await pipeline.earlyReadsSettled
        await context.beginSecondDictation()
        await pipeline.startRecording()
        try await eventually { await pipeline.earlyReadsSettled > settled }

        #expect(await context.readsAfterSecondKeyDown == 2)
        #expect(inserter.received == ["we moved the review"])
        await pipeline.finishRecording()
        #expect(inserter.received == ["we moved the review", " to the next slot"])
    }
}

private actor PendingPasteContext: ContextEngine {
    private var secondDictationBegan = false
    private(set) var readsAfterSecondKeyDown = 0

    func beginSecondDictation() { secondDictationBegan = true }

    func currentContext() async -> AppContext {
        guard secondDictationBegan else { return .fixture(precedingText: "") }
        readsAfterSecondKeyDown += 1
        return .fixture(precedingText: readsAfterSecondKeyDown == 1 ? "" : "we moved the review")
    }
}
