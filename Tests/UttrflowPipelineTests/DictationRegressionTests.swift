import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles
//
// Every double here is private to this file and named for it, so it can sit beside the
// doubles the other pipeline test files declare in the same test target.

/// A place a stage can be held, and released, from a test.
///
/// Everything in this file turns on catching the pipeline in the middle of a stage — a
/// microphone that has not opened yet, a transcription still running — which is the one
/// thing a fake that answers immediately can never be caught doing.
private actor RegressionGate {
    private var isOpen = false
    private var wasReached = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var watchers: [CheckedContinuation<Void, Never>] = []

    /// Called from the code under test: suspends there until the test opens the gate.
    func pass() async {
        wasReached = true
        for watcher in watchers { watcher.resume() }
        watchers.removeAll()
        guard !isOpen else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            held.append(continuation)
        }
    }

    /// Called from a test: returns once something is actually waiting at the gate.
    func waitUntilReached() async {
        guard !wasReached else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            watchers.append(continuation)
        }
    }

    /// Lets everything waiting through, and everything that arrives afterwards.
    func open() {
        isOpen = true
        for continuation in held { continuation.resume() }
        held.removeAll()
    }
}

/// An ``AudioCaptureEngine`` whose `start()` can be held open for as long as a test
/// likes, standing in for the microphone permission prompt on first launch.
private actor RegressionCapture: AudioCaptureEngine {
    enum Call: Sendable, Equatable {
        case start
        case stop
        case cancel
    }

    private(set) var calls: [Call] = []
    private var current: AudioCaptureState = .idle
    private let startGate: RegressionGate?

    init(startGate: RegressionGate? = nil) {
        self.startGate = startGate
    }

    var state: AudioCaptureState { current }

    func start() async throws(AudioCaptureError) {
        calls.append(.start)
        // Recorded before the wait, so a test can tell "the prompt is on screen" from
        // "the microphone is live".
        if let startGate { await startGate.pass() }
        current = .recording
    }

    func stop() async throws(AudioCaptureError) -> AudioSamples {
        calls.append(.stop)
        current = .idle
        return .silence(seconds: 1)
    }

    func cancel() async {
        calls.append(.cancel)
        current = .idle
    }
}

/// A ``SpeechEngine`` that can be held inside the transcription stage.
private final class RegressionSpeech: SpeechEngine, Sendable {
    let kind: SpeechEngineKind = .whisperKit
    private let gate: RegressionGate?
    private let count = Mutex(0)

    init(gate: RegressionGate? = nil) {
        self.gate = gate
    }

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples,
        options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        count.withLock { $0 += 1 }
        if let gate { await gate.pass() }
        return .fixture(text: regressionSpoken)
    }

    /// How many times the pipeline asked for a transcript.
    var transcriptions: Int { count.withLock { $0 } }
}

/// A ``TranscriptCleaning`` that can be held inside the tidying stage and counts what it
/// was asked to tidy.
private final class RegressionCleaner: TranscriptCleaning, Sendable {
    private let gate: RegressionGate?
    private let count = Mutex(0)

    init(gate: RegressionGate? = nil) {
        self.gate = gate
    }

    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        count.withLock { $0 += 1 }
        if let gate { await gate.pass() }
        return TransformationResult(text: regressionTidied, producedBy: .foundationModels)
    }

    /// How many transcripts reached the tidying stage.
    var requests: Int { count.withLock { $0 } }
}

/// A ``TextInserting`` that records every string that reached the user's document.
private final class RegressionInserter: TextInserting, Sendable {
    private let log = Mutex<[String]>([])

    func insert(_ text: String) async throws(TextInsertionError) -> TextInsertionMethod {
        log.withLock { $0.append(text) }
        return .accessibility
    }

    var received: [String] { log.withLock { $0 } }
}

/// A ``HotkeyMonitoring`` that watches for nothing.
///
/// These tests hand the controller its gestures directly through ``submit(_:)``, which
/// is the path the floating button takes; the shortcut never comes into it.
private final class RegressionMonitor: HotkeyMonitoring {
    private let stream: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation

    init() {
        (stream, continuation) = AsyncStream<HotkeyEvent>.makeStream()
    }

    func start(binding: HotkeyBinding) {}

    func stop() {
        continuation.finish()
    }

    var events: AsyncStream<HotkeyEvent> { stream }
}

/// A clock that moves on a little each time it is read.
///
/// The point of the interleaving tests is to submit a press and a release back to back
/// with nothing in between — so there is no moment at which a test could advance a
/// ``ManualClock`` to make the hold long enough to count as a dictation. Letting the
/// clock move itself gives every hold a full step, and the two readings still come from
/// the gestures themselves, in the order they were handled.
private final class SteppingClock: Clock, Sendable {
    typealias Instant = ManualClock.Instant

    private let elapsed = Mutex(Duration.zero)
    private let step: Duration

    init(step: Duration = .seconds(1)) {
        self.step = step
    }

    var now: Instant {
        elapsed.withLock { elapsed in
            elapsed += step
            return Instant(offset: elapsed)
        }
    }

    var minimumResolution: Duration { .nanoseconds(1) }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {}
}

// MARK: - Fixtures

private let regressionSpoken = "um i'll be about twenty minutes late to the meeting"
private let regressionTidied = "I'll be about twenty minutes late to the meeting."

private let regressionOutcome = DictationOutcome(
    text: regressionTidied, method: .accessibility, cleanedBy: .foundationModels,
    insertedInto: "Slack", insertedIntoIdentifier: "com.tinyspeck.slackmacgap",
    spokenFor: .zero,
    changes: AppliedChanges(spokenWords: 10))

// MARK: - Harnesses

/// A controller and everything underneath it, so a test can look at any of it.
private struct GestureHarness {
    let controller: DictationController<SteppingClock>
    let pipeline: DictationPipeline
    let capture: RegressionCapture
    let inserter: RegressionInserter
}

private func makeGestureHarness(startGate: RegressionGate? = nil) -> GestureHarness {
    let capture = RegressionCapture(startGate: startGate)
    let inserter = RegressionInserter()
    let pipeline = DictationPipeline(
        capture: capture,
        speech: RegressionSpeech(),
        cleaner: RegressionCleaner(),
        context: FakeContextEngine(context: .fixture()),
        inserter: inserter,
        // A clock of its own, so the stages cannot move the one the hold is measured on.
        clock: ManualClock()
    )
    return GestureHarness(
        controller: DictationController(
            pipeline: pipeline,
            monitor: RegressionMonitor(),
            activation: .holdToTalk,
            clock: SteppingClock()
        ),
        pipeline: pipeline,
        capture: capture,
        inserter: inserter
    )
}

private func makeRegressionPipeline(
    capture: RegressionCapture = RegressionCapture(),
    speech: RegressionSpeech = RegressionSpeech(),
    cleaner: RegressionCleaner = RegressionCleaner(),
    inserter: RegressionInserter = RegressionInserter()
) -> DictationPipeline {
    DictationPipeline(
        capture: capture,
        speech: speech,
        cleaner: cleaner,
        context: FakeContextEngine(context: .fixture()),
        inserter: inserter,
        metrics: RecordingMetricsRecorder(),
        clock: ManualClock()
    )
}

/// Waits for the dictation to reach an end, and reports how it ended.
///
/// Reading the stream rather than polling keeps the wait exact: it returns the moment
/// the pipeline arrives somewhere it can rest, and never before.
private func endOfDictation(_ stream: AsyncStream<DictationState>) async -> DictationState? {
    for await state in stream {
        switch state {
        case .inserted, .failed: return state
        case .idle, .recording, .transcribing, .tidying: continue
        }
    }
    return nil
}

// MARK: - Tests

@Suite("Dictation regressions: gestures in order, and a cancel that really cancels")
struct DictationRegressionTests {

    // MARK: A press and a release that raced

    /// The failure this prevents: on first launch the user holds the floating button,
    /// speaks, and lets go — and nothing happens. The microphone stays open, the
    /// recording indicator stays lit, and everything they said is thrown away, because
    /// the release was handled while the permission prompt still had `start()`
    /// suspended and returned early on a pipeline that was not listening yet. Both
    /// gestures arrive here as two independent callbacks, exactly as the button
    /// delivers them, with nothing awaited in between for them to queue behind.
    @Test(
        "a press and the release chasing it cannot strand the microphone open",
        .timeLimit(.minutes(1)))
    func aReleaseCannotOvertakeASlowPress() async throws {
        let permissionPrompt = RegressionGate()
        let harness = makeGestureHarness(startGate: permissionPrompt)
        let states = await harness.pipeline.states()

        harness.controller.submit(.pressed)
        harness.controller.submit(.released)

        // The prompt is on screen: `start()` is suspended and the pipeline is not
        // listening — the exact window the release used to slip through.
        await permissionPrompt.waitUntilReached()
        #expect(await harness.pipeline.currentState == .idle)

        await permissionPrompt.open()
        let ending = await endOfDictation(states)

        #expect(ending == .inserted(regressionOutcome))
        #expect(
            await harness.pipeline.currentState.isListening == false,
            "the release must still stop a recording it had to wait for")
        #expect(
            harness.inserter.received == [regressionTidied],
            "what the user said while the prompt was up must not be discarded")
        #expect(await harness.capture.calls == [.start, .stop])
    }

    @Test("a press and the release behind it are handled in order at normal speed too")
    func gesturesKeepTheirOrderWhenNothingIsSlow() async throws {
        let harness = makeGestureHarness()
        let states = await harness.pipeline.states()

        harness.controller.submit(.pressed)
        harness.controller.submit(.released)

        let ending = await endOfDictation(states)

        #expect(ending == .inserted(regressionOutcome))
        #expect(harness.inserter.received == [regressionTidied])
        #expect(
            await harness.capture.calls == [.start, .stop],
            "the release must be handled after the press, never instead of it")
    }

    // MARK: A cancel that arrives after the recording stopped

    /// The failure this prevents: the user cancels a dictation while it is being
    /// transcribed, and moments later the words appear in their document anyway —
    /// possibly in whatever they had switched to in the meantime. Cancelling is
    /// promised to leave no trace, and the promise has to hold for the stages that run
    /// after the microphone has already closed, not only while it is still open.
    @Test(
        "cancelling during transcription inserts nothing and leaves no trace",
        .timeLimit(.minutes(1)))
    func cancellingDuringTranscriptionLeavesNoTrace() async throws {
        let transcribing = RegressionGate()
        let capture = RegressionCapture()
        let cleaner = RegressionCleaner()
        let inserter = RegressionInserter()
        let pipeline = makeRegressionPipeline(
            capture: capture,
            speech: RegressionSpeech(gate: transcribing),
            cleaner: cleaner,
            inserter: inserter
        )
        await pipeline.startRecording()
        let dictation = Task { await pipeline.finishRecording() }
        await transcribing.waitUntilReached()
        #expect(await pipeline.currentState == .transcribing)

        await pipeline.cancel()
        await transcribing.open()
        await dictation.value

        #expect(await pipeline.currentState == .idle, "a cancelled dictation ends nowhere else")
        #expect(inserter.received.isEmpty, "nothing may reach the user's document")
        #expect(cleaner.requests == 0, "an abandoned transcript must not be tidied either")
        #expect(await capture.calls == [.start, .stop, .cancel])
    }

    @Test(
        "cancelling during tidying inserts nothing and leaves no trace",
        .timeLimit(.minutes(1)))
    func cancellingDuringTidyingLeavesNoTrace() async throws {
        let tidying = RegressionGate()
        let cleaner = RegressionCleaner(gate: tidying)
        let inserter = RegressionInserter()
        let pipeline = makeRegressionPipeline(cleaner: cleaner, inserter: inserter)
        await pipeline.startRecording()
        let dictation = Task { await pipeline.finishRecording() }
        await tidying.waitUntilReached()
        #expect(await pipeline.currentState == .tidying)

        await pipeline.cancel()
        await tidying.open()
        await dictation.value

        #expect(await pipeline.currentState == .idle)
        #expect(
            inserter.received.isEmpty,
            "the last stage is the one that would put the words on screen")
        #expect(cleaner.requests == 1, "the cancel arrived while it was already tidying")
    }

    /// A flag saying only "a cancel happened" would still be set when the next
    /// dictation ran, and would throw that one away too — the user cancels once and the
    /// app appears to stop working. The cancel has to name the dictation it abandoned.
    @Test("cancelling one dictation does not touch the next one", .timeLimit(.minutes(1)))
    func aCancelledDictationDoesNotPoisonTheNextOne() async throws {
        let transcribing = RegressionGate()
        let speech = RegressionSpeech(gate: transcribing)
        let inserter = RegressionInserter()
        let pipeline = makeRegressionPipeline(speech: speech, inserter: inserter)
        await pipeline.startRecording()
        let abandoned = Task { await pipeline.finishRecording() }
        await transcribing.waitUntilReached()
        await pipeline.cancel()
        await transcribing.open()
        await abandoned.value
        #expect(inserter.received.isEmpty)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(
            await pipeline.currentState == .inserted(regressionOutcome),
            "the dictation after a cancelled one must run to the end as usual")
        #expect(inserter.received == [regressionTidied])
        #expect(speech.transcriptions == 2)
    }
}
