import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// A place a stage can be held, and released, from a test.
///
/// The pipeline passes through `transcribing` and `tidying` too quickly to be looked at
/// from outside; holding a stage mid-flight is the only way to observe the guards that
/// apply while a dictation is under way.
private actor Gate {
    /// How many arrivals are held; the rest pass straight through.
    ///
    /// Unbounded unless a test says otherwise. A test watching what a *second* caller
    /// does needs that caller to run to its conclusion rather than park beside the
    /// first — a test that deadlocks when the code regresses reports nothing at all.
    private let capacity: Int
    private var arrivals = 0
    private var isOpen = false
    private var wasReached = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var watchers: [CheckedContinuation<Void, Never>] = []

    init(capacity: Int = .max) {
        self.capacity = capacity
    }

    /// Called from a stage: suspends there until the test opens the gate.
    func pass() async {
        arrivals += 1
        wasReached = true
        for watcher in watchers { watcher.resume() }
        watchers.removeAll()
        guard !isOpen, arrivals <= capacity else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            held.append(continuation)
        }
    }

    /// Called from a test: returns once a stage is actually waiting at the gate.
    func waitUntilReached() async {
        guard !wasReached else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            watchers.append(continuation)
        }
    }

    func open() {
        isOpen = true
        for continuation in held { continuation.resume() }
        held.removeAll()
    }
}

/// A ``TranscriptCleaning`` that records what it was asked to tidy and answers as
/// scripted, optionally holding at a gate first.
private final class FakeCleaner: TranscriptCleaning, Sendable {
    private struct State: Sendable {
        var outcome: ScriptedOutcome<TransformationResult, TransformationError>
        var requests: [TransformationRequest] = []
    }

    private let state: Mutex<State>
    private let gate: Gate?

    init(
        outcome: ScriptedOutcome<TransformationResult, TransformationError> = .success(
            TransformationResult(text: tidied, producedBy: .foundationModels)),
        gate: Gate? = nil
    ) {
        self.state = Mutex(State(outcome: outcome))
        self.gate = gate
    }

    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        let outcome = state.withLock {
            state -> ScriptedOutcome<TransformationResult, TransformationError> in
            state.requests.append(request)
            return state.outcome
        }
        if let gate { await gate.pass() }
        return try outcome.resolve()
    }

    var requests: [TransformationRequest] { state.withLock { $0.requests } }
}

/// A ``TextInserting`` that records every string it was handed and answers as scripted.
private final class FakeInserter: TextInserting, Sendable {
    private struct State: Sendable {
        var outcome: ScriptedOutcome<TextInsertionMethod, TextInsertionError>
        var received: [String] = []
    }

    private let state: Mutex<State>

    init(
        outcome: ScriptedOutcome<TextInsertionMethod, TextInsertionError> = .success(.accessibility)
    ) {
        self.state = Mutex(State(outcome: outcome))
    }

    func insert(_ text: String) async throws(TextInsertionError) -> TextInsertionMethod {
        let outcome = state.withLock {
            state -> ScriptedOutcome<TextInsertionMethod, TextInsertionError> in
            state.received.append(text)
            return state.outcome
        }
        return try outcome.resolve()
    }

    var received: [String] { state.withLock { $0.received } }
}

/// A ``SpeechEngine`` that holds at a gate before answering.
///
/// ``FakeSpeechEngine`` returns immediately, which leaves no moment at which the
/// pipeline can be caught in `transcribing`.
private final class GatedSpeechEngine: SpeechEngine, Sendable {
    let kind: SpeechEngineKind = .whisperKit
    private let gate: Gate

    init(gate: Gate) {
        self.gate = gate
    }

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples,
        options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        await gate.pass()
        return .fixture(text: spoken)
    }
}

/// An ``AudioCaptureEngine`` that can be caught mid-`start`.
///
/// ``FakeAudioCaptureEngine`` opens the microphone in one uninterrupted step, which
/// leaves no moment at which a second press can arrive — and that moment is exactly what
/// the guard against overlapping starts exists for. This one also tracks whether the
/// microphone is genuinely live, which is the thing a lost dictation strands.
private actor GatedCaptureEngine: AudioCaptureEngine {
    private let gate: Gate
    private var currentState: AudioCaptureState = .idle
    private(set) var starts = 0
    private(set) var cancels = 0

    init(gate: Gate) {
        self.gate = gate
    }

    var state: AudioCaptureState { currentState }

    func start() async throws(AudioCaptureError) {
        starts += 1
        await gate.pass()
        guard currentState == .idle else { throw .alreadyRecording }
        currentState = .recording
    }

    func stop() async throws(AudioCaptureError) -> AudioSamples {
        guard currentState == .recording else { throw .notRecording }
        currentState = .idle
        return .silence(seconds: 1)
    }

    func cancel() async {
        cancels += 1
        currentState = .idle
    }
}

private let spoken = "um i'll be about twenty minutes late to the meeting"
private let tidied = "I'll be about twenty minutes late to the meeting."

private func makePipeline(
    capture: any AudioCaptureEngine = FakeAudioCaptureEngine(),
    speech: any SpeechEngine = FakeSpeechEngine(
        transcribeOutcome: .success(.fixture(text: spoken))),
    cleaner: FakeCleaner = FakeCleaner(),
    inserter: FakeInserter = FakeInserter(),
    context: FakeContextEngine = FakeContextEngine(context: .fixture())
) -> DictationPipeline {
    DictationPipeline(
        capture: capture,
        speech: speech,
        cleaner: cleaner,
        context: context,
        inserter: inserter,
        metrics: RecordingMetricsRecorder(),
        clock: ManualClock()
    )
}

/// The next `count` states, in order.
///
/// The stream buffers, so a test can run the whole dictation first and read back every
/// step it passed through afterwards.
private func next(
    _ count: Int, from stream: AsyncStream<DictationState>
) async -> [DictationState] {
    var seen: [DictationState] = []
    for await state in stream {
        seen.append(state)
        if seen.count == count { break }
    }
    return seen
}

// MARK: - Tests

@Suite("Dictation pipeline: where a dictation has got to")
struct DictationPipelineStateTests {
    @Test("starts idle")
    func startsIdle() async {
        let pipeline = makePipeline()

        #expect(await pipeline.currentState == .idle)
    }

    @Test("opens the microphone and reports itself recording when a dictation begins")
    func startRecordingListens() async {
        let capture = FakeAudioCaptureEngine()
        let pipeline = makePipeline(capture: capture)

        await pipeline.startRecording()

        #expect(await pipeline.currentState == .recording)
        #expect(await capture.calls.events == [.start])
    }

    @Test("ignores a second start while it is already recording")
    func startWhileRecordingIsIgnored() async {
        let capture = FakeAudioCaptureEngine()
        let pipeline = makePipeline(capture: capture)
        await pipeline.startRecording()

        await pipeline.startRecording()

        #expect(await pipeline.currentState == .recording)
        #expect(await capture.calls.count == 1, "the running recording must not be restarted")
    }

    @Test("ignores a start that arrives while it is transcribing")
    func startWhileTranscribingIsIgnored() async {
        let capture = FakeAudioCaptureEngine()
        let gate = Gate()
        let pipeline = makePipeline(capture: capture, speech: GatedSpeechEngine(gate: gate))
        await pipeline.startRecording()
        let dictation = Task { await pipeline.finishRecording() }
        await gate.waitUntilReached()

        #expect(await pipeline.currentState == .transcribing)
        await pipeline.startRecording()
        #expect(await pipeline.currentState == .transcribing)
        let starts = await capture.calls.events.filter { $0 == .start }.count
        #expect(starts == 1, "a dictation already under way must not be restarted")

        await gate.open()
        await dictation.value
    }

    @Test("ignores a start that arrives while it is tidying")
    func startWhileTidyingIsIgnored() async {
        let capture = FakeAudioCaptureEngine()
        let gate = Gate()
        let pipeline = makePipeline(capture: capture, cleaner: FakeCleaner(gate: gate))
        await pipeline.startRecording()
        let dictation = Task { await pipeline.finishRecording() }
        await gate.waitUntilReached()

        #expect(await pipeline.currentState == .tidying)
        await pipeline.startRecording()
        #expect(await pipeline.currentState == .tidying)
        let starts = await capture.calls.events.filter { $0 == .start }.count
        #expect(starts == 1, "a dictation already under way must not be restarted")

        await gate.open()
        await dictation.value
    }

    @Test("can be started again after the microphone refused to start")
    func failedStartIsRetryable() async {
        let capture = FakeAudioCaptureEngine(startOutcome: .failure(.noInputDevice))
        let pipeline = makePipeline(capture: capture)

        await pipeline.startRecording()
        let refusal = DictationFailure(AudioCaptureError.noInputDevice)
        #expect(await pipeline.currentState == .failed(refusal))

        await capture.setStartOutcome(.ok)
        await pipeline.startRecording()

        #expect(await pipeline.currentState == .recording, "a failed start must be retryable")
    }

    @Test("does nothing when asked to finish while it is not recording")
    func finishWhenNotRecordingIsIgnored() async {
        let capture = FakeAudioCaptureEngine()
        let inserter = FakeInserter()
        let pipeline = makePipeline(capture: capture, inserter: inserter)

        await pipeline.finishRecording()

        #expect(await pipeline.currentState == .idle)
        #expect(await capture.calls.isEmpty, "there was no recording to stop")
        #expect(inserter.received.isEmpty)
    }

    @Test("does not run a second time when a finished dictation is finished again")
    func finishAfterInsertionIsIgnored() async {
        let inserter = FakeInserter()
        let pipeline = makePipeline(inserter: inserter)
        await pipeline.startRecording()
        await pipeline.finishRecording()

        await pipeline.finishRecording()

        #expect(inserter.received == [tidied])
    }

    @Test("passes through transcribing, then tidying, then inserted")
    func happyPathVisitsEveryStageInOrder() async {
        let pipeline = makePipeline()
        let states = await pipeline.states()

        await pipeline.startRecording()
        await pipeline.finishRecording()

        let inserted = DictationOutcome(
            text: tidied, method: .accessibility, cleanedBy: .foundationModels,
            insertedInto: "Slack", insertedIntoIdentifier: "com.tinyspeck.slackmacgap",
            spokenFor: .zero, changes: AppliedChanges(spokenWords: 10))
        #expect(
            await next(5, from: states) == [
                .idle, .recording, .transcribing, .tidying, .inserted(inserted),
            ])
    }

    /// The history page labels a dictation with where it went, and the artboard has
    /// always shown it. Until now nothing recorded it, so the label had no source.
    ///
    /// It is taken from the context read for tidying rather than asked for again at
    /// insertion time: by the moment the interface wants the label the user has usually
    /// switched away, and a fresh read would confidently name the wrong application.
    @Test("the finished dictation says which application it went into")
    func outcomeNamesTheTargetApplication() async {
        let pipeline = makePipeline(context: FakeContextEngine(context: .fixture(applicationName: "Notes")))

        await pipeline.startRecording()
        await pipeline.finishRecording()

        guard case .inserted(let outcome) = await pipeline.currentState else {
            Issue.record("expected the dictation to finish")
            return
        }
        #expect(outcome.insertedInto == "Notes")
    }

    /// The name is what the row is labelled with; the identifier is what its icon is
    /// looked up by. The context has known it all along and the pipeline used to drop
    /// it, which left the interface guessing which of the apps called "Notes" it meant.
    @Test("the finished dictation carries the application's bundle identifier")
    func outcomeCarriesTheBundleIdentifier() async {
        let pipeline = makePipeline(
            context: FakeContextEngine(
                context: .fixture(
                    applicationName: "Claude", bundleIdentifier: "com.anthropic.claudefordesktop")))

        await pipeline.startRecording()
        await pipeline.finishRecording()

        guard case .inserted(let outcome) = await pipeline.currentState else {
            Issue.record("expected the dictation to finish")
            return
        }
        #expect(outcome.insertedIntoIdentifier == "com.anthropic.claudefordesktop")
    }

    /// An unidentifiable app is left unnamed rather than guessed.
    @Test("an application it could not identify is left unnamed")
    func outcomeLeavesAnUnknownApplicationUnnamed() async {
        let pipeline = makePipeline(context: FakeContextEngine(context: .unknown))

        await pipeline.startRecording()
        await pipeline.finishRecording()

        guard case .inserted(let outcome) = await pipeline.currentState else {
            Issue.record("expected the dictation to finish")
            return
        }
        #expect(outcome.insertedInto == nil)
        #expect(outcome.insertedIntoIdentifier == nil, "and is not identified either")
    }

    @Test("leaves no trace when cancelled while recording")
    func cancelWhileRecordingLeavesNoTrace() async {
        let capture = FakeAudioCaptureEngine()
        let speech = FakeSpeechEngine()
        let cleaner = FakeCleaner()
        let inserter = FakeInserter()
        let pipeline = makePipeline(
            capture: capture, speech: speech, cleaner: cleaner, inserter: inserter)
        await pipeline.startRecording()

        await pipeline.cancel()

        #expect(await pipeline.currentState == .idle)
        #expect(await capture.calls.events == [.start, .cancel])
        #expect(await speech.transcribeCalls.isEmpty, "cancelled audio must never be transcribed")
        #expect(cleaner.requests.isEmpty)
        #expect(inserter.received.isEmpty)
    }

    @Test("does nothing when cancelled while idle")
    func cancelWhileIdleIsSafe() async {
        let speech = FakeSpeechEngine()
        let pipeline = makePipeline(speech: speech)

        await pipeline.cancel()

        #expect(await pipeline.currentState == .idle)
        #expect(await speech.transcribeCalls.isEmpty)
    }

    @Test("returns to idle when a finished dictation is acknowledged, however it ended")
    func acknowledgeClearsAFinishedDictation() async {
        let inserted = makePipeline()
        await inserted.startRecording()
        await inserted.finishRecording()

        await inserted.acknowledge()
        #expect(await inserted.currentState == .idle)

        let failed = makePipeline(
            capture: FakeAudioCaptureEngine(startOutcome: .failure(.noInputDevice)))
        await failed.startRecording()

        await failed.acknowledge()
        #expect(await failed.currentState == .idle)
    }

    @Test("ignores an acknowledgement that arrives mid-dictation")
    func acknowledgeWhileBusyIsIgnored() async {
        let pipeline = makePipeline()
        await pipeline.startRecording()

        await pipeline.acknowledge()

        #expect(await pipeline.currentState == .recording)
    }

    /// Saying nothing is not an error and has nothing to insert; showing a failure for it
    /// would turn a stray key press into something the user has to dismiss.
    @Test("returns quietly to idle when nothing was said")
    func silenceEndsQuietly() async {
        let cleaner = FakeCleaner()
        let inserter = FakeInserter()
        let pipeline = makePipeline(
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: "   "))),
            cleaner: cleaner,
            inserter: inserter
        )
        let states = await pipeline.states()

        await pipeline.startRecording()
        await pipeline.finishRecording()

        // Not `.idle`. Returning quietly is indistinguishable from the app being broken:
        // the user holds the key, speaks, lets go, and nothing whatever happens.
        let heardNothing = DictationState.failed(DictationFailure(SpeechEngineError.nothingHeard))
        #expect(await next(4, from: states) == [.idle, .recording, .transcribing, heardNothing])
        #expect(await pipeline.currentState == heardNothing)
        #expect(cleaner.requests.isEmpty)
        #expect(inserter.received.isEmpty, "there was nothing to insert")
    }

    @Test("counts only a dictation under way as busy, and only recording as listening")
    func busyAndListeningPerState() {
        let inserted = DictationState.inserted(
            DictationOutcome(
                text: tidied, method: .accessibility, cleanedBy: .foundationModels,
                insertedInto: "Slack", insertedIntoIdentifier: "com.tinyspeck.slackmacgap",
                spokenFor: .zero))
        let failed = DictationState.failed(
            DictationFailure(
                message: "No microphone was found.", recovery: .retry, severity: .blocking))

        #expect(!DictationState.idle.isBusy)
        #expect(DictationState.recording.isBusy)
        #expect(DictationState.transcribing.isBusy)
        #expect(DictationState.tidying.isBusy)
        #expect(!inserted.isBusy)
        #expect(!failed.isBusy)

        #expect(!DictationState.idle.isListening)
        #expect(DictationState.recording.isListening)
        #expect(!DictationState.transcribing.isListening)
        #expect(!DictationState.tidying.isListening)
        #expect(!inserted.isListening)
        #expect(!failed.isListening)
    }

    /// The interface used to say Ready over a recogniser that had failed to load, and
    /// the user found out one wasted dictation later. `prepare` stays non-throwing so
    /// launch code has nothing to decide, but the failure has to reach the screen.
    @Test("shows the failure when the recogniser will not start")
    func prepareFailureReachesTheInterface() async {
        let speech = FakeSpeechEngine(prepareOutcome: .failure(.modelNotInstalled))
        let pipeline = makePipeline(speech: speech)

        await pipeline.prepare()

        #expect(
            await pipeline.currentState == .failed(DictationFailure(SpeechEngineError.modelNotInstalled)),
            "a recogniser that cannot start must not be reported as ready")
    }

    @Test("clears the notice when a second attempt to start the recogniser works")
    func successfulPrepareClearsAnEarlierFailure() async {
        let speech = FakeSpeechEngine(prepareOutcome: .failure(.modelNotInstalled))
        let pipeline = makePipeline(speech: speech)
        await pipeline.prepare()

        await speech.setPrepareOutcome(.ok)
        await pipeline.prepare()

        #expect(await pipeline.currentState == .idle)
    }

    /// Loading the model behind a dictation that is already running must not overwrite
    /// where that dictation has got to.
    @Test("leaves a dictation under way alone when asked to prepare")
    func prepareWhileBusyIsIgnored() async {
        let speech = FakeSpeechEngine(prepareOutcome: .failure(.modelNotInstalled))
        let pipeline = makePipeline(speech: speech)
        await pipeline.startRecording()

        await pipeline.prepare()

        #expect(await pipeline.currentState == .recording)
    }

    /// The worst thing this product could do. `RuleBasedTransformer` strips fillers and
    /// nothing else, so "um" tidies to the empty string — and the Accessibility route
    /// inserts by replacing the selected text, so inserting nothing DELETES whatever the
    /// user had selected, while the interface reports a dictation that worked.
    @Test(
        "inserts nothing when tidying leaves nothing, rather than deleting the selection",
        arguments: ["", "   "])
    func tidyingToNothingInsertsNothing(tidiedAway: String) async {
        let inserter = FakeInserter()
        let pipeline = makePipeline(
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: "um"))),
            cleaner: FakeCleaner(
                outcome: .success(TransformationResult(text: tidiedAway, producedBy: .rules))),
            inserter: inserter
        )
        let states = await pipeline.states()

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(
            await next(5, from: states) == [
                .idle, .recording, .transcribing, .tidying,
                .failed(DictationFailure(SpeechEngineError.nothingHeard)),
            ],
            "a dictation with nothing in it says so, and is never an insertion")
        #expect(inserter.received.isEmpty, "an empty insertion would delete the user's selection")
        #expect(
            await pipeline.currentState
                == .failed(DictationFailure(SpeechEngineError.nothingHeard)),
            "the user must be told, softly, rather than left wondering")
    }

    /// The menu bar's Start Dictation calls straight into the pipeline, so it can race
    /// the hotkey. The guard used to be read before the microphone was awaited and the
    /// state set only after, so both presses got through: the second `start` threw
    /// `alreadyRecording`, the pipeline settled in `failed` — which is not busy — and
    /// nothing was left that `finishRecording` would act on, with the microphone live.
    @Test("opens the microphone once when two presses arrive together")
    func overlappingStartsOpenTheMicrophoneOnce() async {
        // Holds only the first arrival, so the racing press runs to whatever conclusion
        // it reaches and the test can look at it instead of waiting for it.
        let gate = Gate(capacity: 1)
        let capture = GatedCaptureEngine(gate: gate)
        let pipeline = makePipeline(capture: capture)

        let first = Task { await pipeline.startRecording() }
        await gate.waitUntilReached()
        await Task { await pipeline.startRecording() }.value

        #expect(await capture.starts == 1, "the microphone must not be opened twice")

        await gate.open()
        await first.value

        #expect(await pipeline.currentState == .recording)

        await pipeline.finishRecording()
        #expect(await capture.state == .idle, "the microphone must not be left live")
    }

    @Test("closes the microphone again when a cancel lands while it is opening")
    func cancellingWhileTheMicrophoneOpensClosesItAgain() async {
        let gate = Gate()
        let capture = GatedCaptureEngine(gate: gate)
        let pipeline = makePipeline(capture: capture)

        let start = Task { await pipeline.startRecording() }
        await gate.waitUntilReached()
        await pipeline.cancel()
        await gate.open()
        await start.value

        #expect(await pipeline.currentState == .idle)
        #expect(
            await capture.state == .idle,
            "a dictation abandoned while starting must not leave the microphone live")
    }

    @Test("hands a watcher that arrives late the state it is in now")
    func lateWatcherSeesCurrentState() async {
        let pipeline = makePipeline()
        await pipeline.startRecording()

        let states = await pipeline.states()

        #expect(
            await next(1, from: states) == [.recording],
            "a watcher must not be left blank until something next happens")
    }
}
