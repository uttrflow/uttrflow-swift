// Tests what a dictation tried while the speech model loads is answered with.
import Testing
import Synchronization

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// A recogniser whose load holds until the test calls `finishHungLoads()`, then fails with `failure` if given.
private func slowLoading(failing failure: SpeechEngineError? = nil) -> FakeSpeechEngine {
    FakeSpeechEngine(
        prepareOutcome: failure.map { .failure($0) } ?? .ok,
        transcribeOutcome: .success(.fixture(text: "Loaded and listening.")), prepareHangs: true)
}

/// A recogniser whose load returns at once, failing with `failure` if given.
private func loadedAtOnce(failing failure: SpeechEngineError? = nil) -> FakeSpeechEngine {
    FakeSpeechEngine(prepareOutcome: failure.map { .failure($0) } ?? .ok)
}

extension FakeSpeechEngine {
    /// Returns once the load has been asked for and is held.
    fileprivate func waitUntilLoading() async {
        while await prepareCalls.isEmpty { await Task.yield() }
    }
}

private func makePipeline(
    speech: any SpeechEngine, capture: FakeAudioCaptureEngine
) -> DictationPipeline {
    DictationPipeline(
        capture: capture, speech: speech, cleaner: FakeTranscriptCleaner(),
        context: FakeContextEngine(context: .fixture()), inserter: FakeTextInserter(),
        metrics: RecordingMetricsRecorder(), clock: ManualClock())
}

/// Records start cues without playing audio.
private final class LoadingCueSpy: RecordingCueing {
    private let starts = Mutex(0)

    func playStart() { starts.withLock { $0 += 1 } }
    func playStop() {}
    func playWarning() {}
    func playDiscarded() {}

    var startCount: Int { starts.withLock { $0 } }
}

/// Accepts a binding without connecting to the system hotkey service.
private struct LoadingHotkeyMonitor: HotkeyMonitoring {
    @MainActor func start(binding: HotkeyBinding) throws(HotkeyError) {}
    func stop() {}
    var events: AsyncStream<HotkeyEvent> { AsyncStream { _ in } }
}

/// The notice a refused attempt leaves, spelled out so the words on screen are pinned here.
private let refusal = DictationFailure(
    message: "Speech model still loading…", recovery: nil, severity: .informational)

extension DictationPipeline {
    /// Returns once the read taken at key-down has settled.
    fileprivate func waitForEarlyRead() async {
        while recordingDestination == nil { await Task.yield() }
    }
}

// MARK: - Tests

@Suite("Dictating while the speech model loads")
struct DictationPipelineLoadingTests {
    @Test("records through the load and delivers the words once the model is ready")
    func attemptDuringLoadKeepsTheSpeech() async {
        let speech = slowLoading()
        let capture = FakeAudioCaptureEngine()
        let inserter = FakeTextInserter()
        let pipeline = DictationPipeline(
            capture: capture, speech: speech, cleaner: FakeTranscriptCleaner(),
            context: FakeContextEngine(context: .fixture()), inserter: inserter,
            metrics: RecordingMetricsRecorder(), clock: ManualClock())
        let loading = Task { await pipeline.prepare() }
        await speech.waitUntilLoading()

        await pipeline.startRecording()
        #expect(await pipeline.currentState == .recording)
        #expect(await capture.calls.events == [.start])

        let finishing = Task { await pipeline.finishRecording() }
        await speech.finishHungLoads()
        await loading.value
        await finishing.value
        #expect(await pipeline.isReady)
        #expect(!inserter.received.isEmpty)
    }

    @Test("words finished after a load, with the person now in another app, are copied and not typed there")
    func movedAwayDuringTheLoadCopies() async {
        let speech = slowLoading()
        let inserter = FakeTextInserter()
        let clipboard = FakeTextInserter()
        let context = FakeContextEngine(
            context: AppContext(applicationName: "Fixture Notes", bundleIdentifier: "com.example.notes"))
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: speech,
            cleaner: FakeTranscriptCleaner(), context: context, inserter: inserter,
            metrics: RecordingMetricsRecorder(), clipboard: clipboard, clock: ContinuousClock())
        let loading = Task { await pipeline.prepare() }
        await speech.waitUntilLoading()
        await pipeline.startRecording()
        await pipeline.waitForEarlyRead()
        await context.setContext(
            AppContext(applicationName: "Fixture Mail", bundleIdentifier: "com.example.mail"))
        let finishing = Task { await pipeline.finishRecording() }
        await speech.finishHungLoads()
        await loading.value
        await finishing.value

        #expect(inserter.received.isEmpty, "never typed into the app the person moved to")
        #expect(clipboard.received.count == 1, "the words are kept on the clipboard")
    }

    @Test("words finished after a load go to the field when the person stayed")
    func stayedDuringTheLoadInserts() async {
        let speech = slowLoading()
        let inserter = FakeTextInserter()
        let clipboard = FakeTextInserter()
        let context = FakeContextEngine(
            context: AppContext(applicationName: "Fixture Notes", bundleIdentifier: "com.example.notes"))
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: speech,
            cleaner: FakeTranscriptCleaner(), context: context, inserter: inserter,
            metrics: RecordingMetricsRecorder(), clipboard: clipboard, clock: ContinuousClock())
        let loading = Task { await pipeline.prepare() }
        await speech.waitUntilLoading()
        await pipeline.startRecording()
        await pipeline.waitForEarlyRead()
        let finishing = Task { await pipeline.finishRecording() }
        await speech.finishHungLoads()
        await loading.value
        await finishing.value

        #expect(inserter.received.count == 1)
        #expect(clipboard.received.isEmpty)
    }

    @Test("a load slower than the transcription limit does not time the dictation out")
    func slowLoadOutlastsTheTranscriptionLimit() async {
        let speech = slowLoading()
        let clock = ManualClock()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: speech,
            cleaner: FakeTranscriptCleaner(), context: FakeContextEngine(context: .fixture()),
            inserter: FakeTextInserter(), metrics: RecordingMetricsRecorder(), clock: clock)
        let loading = Task { await pipeline.prepare() }
        await speech.waitUntilLoading()
        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }

        while await pipeline.currentState != .transcribing { await Task.yield() }
        // Well past the recognition limit, in steps, so any limit waiting now runs out.
        for _ in 0..<4 {
            await clock.advanceWhenSomethingIsWaiting(by: StageTimeout.transcription + .seconds(60))
            for _ in 0..<50 { await Task.yield() }
        }
        if case .failed(let failure) = await pipeline.currentState {
            Issue.record("the dictation failed while the model was loading: \(failure)")
        }
        await speech.finishHungLoads()
        await loading.value
        await finishing.value
        #expect(await !pipeline.isLoading)
    }

    @Test("dictates as before once the load finishes")
    func loadFinishingRestoresDictation() async {
        let speech = slowLoading()
        let capture = FakeAudioCaptureEngine()
        let pipeline = makePipeline(speech: speech, capture: capture)
        let loading = Task { await pipeline.prepare() }
        await speech.waitUntilLoading()

        await speech.finishHungLoads()
        await loading.value

        #expect(await pipeline.currentState == .idle)
        #expect(await pipeline.isReady)
        #expect(await !pipeline.isLoading)
        await pipeline.startRecording()
        #expect(await pipeline.currentState == .recording)
        #expect(await capture.calls.events == [.start])
    }

    @Test("a load that fails is not left loading, and says so")
    func failedLoadIsNotLoading() async {
        let failure = SpeechEngineError.modelLoadFailed(description: "fixture")
        let pipeline = makePipeline(
            speech: loadedAtOnce(failing: failure),
            capture: FakeAudioCaptureEngine())

        await pipeline.prepare()

        #expect(await !pipeline.isLoading)
        #expect(await !pipeline.isReady)
        #expect(
            await pipeline.currentState
                == .failed(DictationFailure(failure, speechEngineKind: .whisperKit)))
    }

    @Test("a preparation failure keeps its engine and typed cause")
    func failedLoadKeepsItsCause() async throws {
        let failure = SpeechEngineError.modelLoadFailed(description: "weights unreadable")
        let pipeline = makePipeline(
            speech: loadedAtOnce(failing: failure),
            capture: FakeAudioCaptureEngine())

        await pipeline.prepare()

        guard case .failed(let notice) = await pipeline.currentState else {
            Issue.record("the failed load did not reach pipeline state")
            return
        }
        #expect(notice.speechEngineKind == .whisperKit)
        #expect(notice.speechEngineError == failure)
    }

    @Test(
        "a failed load keeps its class for Diagnostics",
        arguments: [
            (SpeechEngineError.modelDamaged(fileCount: 1), SpeechLoadFailureClass.damaged),
            (.modelNotInstalled, .missingFiles),
            (.modelLoadFailed(description: "fixture"), .other),
            (.modelLoadFailed(description: "fixture", outOfMemory: true), .outOfMemory),
        ])
    func failedLoadKeepsItsClass(failure: SpeechEngineError, expected: SpeechLoadFailureClass) async {
        let pipeline = makePipeline(
            speech: loadedAtOnce(failing: failure),
            capture: FakeAudioCaptureEngine())

        await pipeline.prepare()

        #expect(await pipeline.lastLoadFailure == expected)
    }

    @Test("a load that works clears the class an earlier failure left")
    func workingLoadClearsTheClass() async {
        let pipeline = makePipeline(speech: loadedAtOnce(), capture: FakeAudioCaptureEngine())

        await pipeline.prepare()

        #expect(await pipeline.lastLoadFailure == nil)
    }

    @Test("a pipeline nobody prepared dictates at once, loading on demand as before")
    func unpreparedPipelineIsNotRefused() async {
        let capture = FakeAudioCaptureEngine()
        let pipeline = makePipeline(speech: FakeSpeechEngine(), capture: capture)

        await pipeline.startRecording()

        #expect(await pipeline.currentState == .recording)
    }

    @Test("a modifier press during the load becomes the recording")
    func modifierPressDuringLoadIsAdopted() async {
        let speech = slowLoading()
        let capture = FakeAudioCaptureEngine()
        let pipeline = makePipeline(speech: speech, capture: capture)
        let loading = Task { await pipeline.prepare() }
        await speech.waitUntilLoading()

        await pipeline.beginModifierPress(measuring: { .zero })
        let adopted = await pipeline.adoptModifierPress()

        #expect(adopted)
        #expect(await capture.calls.events == [.start])
        await pipeline.cancel()
        await speech.finishHungLoads()
        await loading.value
    }

    @Test("the refusal is the shared notice, informational and with nothing to press")
    func refusalIsTheSharedNotice() {
        #expect(DictationFailure.stillLoading == refusal)
        #expect(DictationFailure.stillLoading.message == SpeechModelLoad.refusal)
    }
}

@Suite("A speech model load that never returns", .timeLimit(.minutes(1)))
struct DictationPipelineLoadDeadlineTests {
    private func makePipeline(speech: FakeSpeechEngine, clock: ManualClock) -> DictationPipeline {
        DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: speech, cleaner: FakeTranscriptCleaner(),
            context: FakeContextEngine(context: .fixture()), inserter: FakeTextInserter(),
            clock: clock, speechLoadLimit: .seconds(300))
    }

    @Test("fails with the retry once the limit passes, and is no longer loading")
    func stuckLoadFailsAtTheLimit() async {
        let clock = ManualClock()
        let speech = FakeSpeechEngine(prepareHangs: true)
        let pipeline = makePipeline(speech: speech, clock: clock)

        let loading = Task { await pipeline.prepare() }
        await clock.advanceWhenSomethingIsWaiting(by: .seconds(300))
        await loading.value

        #expect(await !pipeline.isLoading)
        #expect(await !pipeline.isReady)
        #expect(await pipeline.lastLoadFailure == .timedOut)
        guard case .failed(let failure) = await pipeline.currentState else {
            Issue.record("a stuck load was not reported as failed")
            return
        }
        #expect(failure.recovery == .retry)
        await speech.finishHungLoads()
    }

    @Test("a retry after the stuck load finally ends loads as usual")
    func retryAfterTheStuckLoadEnds() async {
        let clock = ManualClock()
        let speech = FakeSpeechEngine(prepareHangs: true)
        let pipeline = makePipeline(speech: speech, clock: clock)
        let loading = Task { await pipeline.prepare() }
        await clock.advanceWhenSomethingIsWaiting(by: .seconds(300))
        await loading.value

        await speech.finishHungLoads()
        await pipeline.prepare()

        #expect(await pipeline.isReady)
        #expect(await pipeline.currentState == .idle)
    }

    @Test("a load inside the limit is not cut short")
    func loadInsideTheLimitSucceeds() async {
        let pipeline = makePipeline(speech: FakeSpeechEngine(), clock: ManualClock())

        await pipeline.prepare()

        #expect(await pipeline.isReady)
        #expect(await !pipeline.isLoading)
    }
}
