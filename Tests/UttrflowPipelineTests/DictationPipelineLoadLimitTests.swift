// Tests what the shipped speech model load limit decides for loads of 20 s, 300 s and 900 s, on a virtual clock.
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A recogniser whose load is a compile of a fixed length on the test's clock, lost if its task is cancelled.
private final class CompilingSpeechEngine: SpeechEngine, Sendable {
    let kind = SpeechEngineKind.whisperKit
    private let clock: ManualClock
    private let finishesAt: ManualClock.Instant
    private let started = Mutex(false)

    init(compiling length: Duration, on clock: ManualClock) {
        self.clock = clock
        finishesAt = clock.now.advanced(by: length)
    }

    var hasStarted: Bool { started.withLock { $0 } }

    func prepare() async throws(SpeechEngineError) {
        started.withLock { $0 = true }
        do {
            try await clock.sleep(until: finishesAt, tolerance: nil)
        } catch {
            throw .modelLoadFailed(description: "the compile was cancelled")
        }
    }

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        .fixture()
    }
}

@Suite("The speech model load limit against loads of different lengths", .timeLimit(.minutes(1)))
struct DictationPipelineLoadLimitTests {
    /// A pipeline at the shipped limit, already loading a model whose compile takes `length`.
    private func startLoading(
        _ length: Duration, on clock: ManualClock
    ) async -> (DictationPipeline, Task<Void, Never>) {
        let speech = CompilingSpeechEngine(compiling: length, on: clock)
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: speech, cleaner: FakeTranscriptCleaner(),
            context: FakeContextEngine(context: .fixture()), inserter: FakeTextInserter(), clock: clock)
        let loading = Task { await pipeline.prepare() }
        while !speech.hasStarted { await Task.yield() }
        for _ in 0..<50 { await Task.yield() }
        return (pipeline, loading)
    }

    /// Moves the clock to `time` in ten-second steps, letting every waiter run between them.
    private func advance(_ clock: ManualClock, to time: Duration) async {
        while clock.now.offset < time {
            clock.advance(by: .seconds(10))
            for _ in 0..<50 { await Task.yield() }
        }
    }

    @Test("a load inside the limit ends ready with no failure reported", arguments: [20, 300])
    func loadInsideTheLimit(seconds: Int) async {
        let clock = ManualClock()
        let (pipeline, loading) = await startLoading(.seconds(seconds), on: clock)

        await advance(clock, to: .seconds(seconds))
        await loading.value

        #expect(await pipeline.isReady)
        #expect(await pipeline.lastLoadFailure == nil)
        #expect(await pipeline.currentState == .idle)
    }

    @Test("a load past the limit is reported at the limit, keeps compiling, and ends ready")
    func loadPastTheLimit() async {
        let clock = ManualClock()
        let (pipeline, loading) = await startLoading(.seconds(900), on: clock)

        await advance(clock, to: StageTimeout.speechModelLoad + .seconds(10))
        await loading.value
        #expect(await pipeline.lastLoadFailure == .timedOut)
        guard case .failed(let failure) = await pipeline.currentState else {
            Issue.record("a load past the limit was not reported at the limit")
            return
        }
        #expect(failure.recovery == .retry)

        await advance(clock, to: .seconds(900))
        for _ in 0..<500 {
            if await pipeline.isReady { break }
            await Task.yield()
        }

        #expect(await pipeline.isReady)
        #expect(await pipeline.lastLoadFailure == nil)
        #expect(await pipeline.currentState == .idle)
    }
}
