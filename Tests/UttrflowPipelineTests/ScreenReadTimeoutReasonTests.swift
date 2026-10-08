import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A ``ContextEngine`` that takes the read and never answers, the way a stalled application does.
private actor StalledContextEngine: ContextEngine {
    let calls = CallLog<Void>()

    func currentContext() async -> AppContext {
        await calls.append(())
        while !Task.isCancelled { try? await Task.sleep(for: .seconds(3_600)) }
        return .unknown
    }
}

@Suite("A screen read past its limit")
struct ScreenReadTimeoutReasonTests {
    @Test("hands the cleaner a context that says it timed out, not one that looks unknown")
    func cleanerSeesTheTimeout() async {
        let clock = ManualClock()
        let context = StalledContextEngine()
        let cleaner = FakeTranscriptCleaner()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: FakeSpeechEngine(transcribeOutcome: .success(Transcription(text: "what I said"))),
            cleaner: cleaner, context: context, inserter: FakeTextInserter(), clock: clock)

        await pipeline.startRecording()
        while await context.calls.count == 0 { await Task.yield() }
        while !clock.advanceIfSomethingIsWaiting(exactly: StageTimeout.screenRead) { await Task.yield() }
        await pipeline.finishRecording()

        #expect(cleaner.requests.map(\.context.unavailable) == [.timedOut])
        #expect(cleaner.requests.first?.context != .unknown)
    }
}
