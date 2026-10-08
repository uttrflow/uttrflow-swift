// Tests when a dictation's last screen reading may stand in for the read before writing, and when it may not.

import Testing
import UttrflowCore
import UttrflowTestSupport

@testable import UttrflowPipeline

/// A screen no key, click or switch ever reaches, which counts how often it is read.
private actor QuietScreen: ContextEngine {
    private(set) var reads = 0

    func currentContext() async -> AppContext {
        reads += 1
        return .fixture(precedingText: "Dear team")
    }

    func inputsSeen() async -> Int? { 0 }
}

@Suite("Dictation pipeline: reusing the last screen reading", .timeLimit(.minutes(1)))
struct DictationScreenReadsTests {
    @Test("a reading stands in for the next only when complete, counted, and no input came since")
    func onlyACompleteCountedReadingIsReused() {
        var reads = DictationScreenReads()
        reads.record(.fixture(), took: .milliseconds(3), inputsBefore: 4)
        #expect(reads.unchanged(inputsNow: 4) == .fixture())
        #expect(reads.unchanged(inputsNow: 5) == nil, "a key, click or switch came since")
        #expect(reads.cost == ScreenReadCost(reads: 1, duration: .milliseconds(3)))

        reads.record(AppContext(unavailable: .timedOut), took: .milliseconds(100), inputsBefore: 4)
        #expect(reads.unchanged(inputsNow: 4) == nil, "the read was cut short")
        reads.record(.fixture(), took: .milliseconds(3), inputsBefore: nil)
        #expect(reads.unchanged(inputsNow: 4) == nil, "no input was counted before it")
    }

    @Test("a dictation begun while an earlier paste may still land reads the caret again before writing")
    func aPasteStillLandingIsReadAgain() async throws {
        let clock = ManualClock()
        let screen = QuietScreen()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(),
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: "see you there"))),
            cleaner: FakeTranscriptCleaner(producedBy: .rules), context: screen,
            inserter: FakeTextInserter(.success(InsertionAttempt(.pasteboard, arrival: .unconfirmed))),
            clock: clock)

        await pipeline.startRecording()
        await pipeline.finishRecording()
        #expect(
            await screen.reads == 1,
            "nothing could have moved the caret, so the first reading was written against")

        let settled = await pipeline.earlyReadsSettled
        await pipeline.startRecording()
        // The paste never shows at the caret, so the wait for it runs out one poll at a time.
        while await pipeline.earlyReadsSettled == settled {
            clock.advanceIfSomethingIsWaiting(exactly: .milliseconds(40))
            await Task.yield()
        }
        let readWhileWaiting = await screen.reads
        await pipeline.finishRecording()

        #expect(await screen.reads == readWhileWaiting + 1)
    }
}
