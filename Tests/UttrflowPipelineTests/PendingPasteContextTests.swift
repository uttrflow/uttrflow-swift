import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("An unconfirmed paste outdates the next dictation's first caret read", .timeLimit(.minutes(1)))
struct PendingPasteContextTests {
    @Test("An immediately returned stale caret is retried before the second dictation finishes")
    func staleCaretIsRetriedBeforeKeyUp() async throws {
        let context = PendingPasteContext()
        let inserter = PendingPasteInserter()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: PendingPasteSpeech(),
            cleaner: FakeTranscriptCleaner(producedBy: .foundationModels),
            context: context, inserter: inserter)

        await pipeline.startRecording()
        await pipeline.finishRecording()
        let settled = await pipeline.earlyReadsSettled
        await context.beginSecondDictation()
        await pipeline.startRecording()
        try await eventually { await pipeline.earlyReadsSettled > settled }

        #expect(await context.readsAfterSecondKeyDown == 2)
        #expect(await inserter.received == ["we moved the review"])
        await pipeline.finishRecording()
        #expect(await inserter.received == ["we moved the review", " to the next slot"])
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

private actor PendingPasteSpeech: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private var lines = ["we moved the review", "to the next slot"]

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        Transcription(text: lines.removeFirst(), audioDuration: audio.duration)
    }
}

private actor PendingPasteInserter: TextInserting {
    private(set) var received: [String] = []

    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        received.append(text)
        return InsertionAttempt(.pasteboard, arrival: .unconfirmed)
    }
}
