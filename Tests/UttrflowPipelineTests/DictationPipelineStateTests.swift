// Tests the pipeline's states and the guards that apply mid-dictation.
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// A place a stage can be held and released from a test, so a dictation can be caught mid-flight.
private actor Gate {
    /// How many arrivals are held; the rest pass through, so a second caller can run to its conclusion.
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

/// A ``SpeechEngine`` that holds at a gate, so the pipeline can be caught in `transcribing`.
private final class GatedSpeechEngine: SpeechEngine, Sendable {
    let kind: SpeechEngineKind = .whisperKit
    private let gate: Gate
    private let error: SpeechEngineError?

    init(gate: Gate, error: SpeechEngineError? = nil) {
        self.gate = gate
        self.error = error
    }

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples,
        options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        await gate.pass()
        if let error { throw error }
        return .fixture(text: spoken)
    }
}

/// An ``AudioCaptureEngine`` that can be caught mid-`start`, and knows whether the microphone is live.
private actor GatedCaptureEngine: AudioCaptureEngine {
    private let gate: Gate
    // Consumed on the first throw, so a retry after a scripted failure opens normally.
    private var startError: AudioCaptureError?
    private var currentState: AudioCaptureState = .idle
    private(set) var starts = 0
    private(set) var cancels = 0

    init(gate: Gate, startError: AudioCaptureError? = nil) {
        self.gate = gate
        self.startError = startError
    }

    var state: AudioCaptureState { currentState }

    func start() async throws(AudioCaptureError) {
        starts += 1
        await gate.pass()
        if let startError {
            self.startError = nil
            throw startError
        }
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
private let tidiedAnswer = ScriptedSequence<TransformationResult, TransformationError>(
    .success(TransformationResult(text: tidied, producedBy: .foundationModels)))

private func makePipeline(
    capture: any AudioCaptureEngine = FakeAudioCaptureEngine(),
    speech: any SpeechEngine = FakeSpeechEngine(
        transcribeOutcome: .success(.fixture(text: spoken))),
    cleaner: FakeTranscriptCleaner = FakeTranscriptCleaner(answering: tidiedAnswer),
    inserter: FakeTextInserter = FakeTextInserter(),
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

/// The next `count` states in order; the stream buffers, so they can be read back afterwards.
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

    /// The user is already speaking while this runs, so Diagnostics has to be able to say how long it took.
    @Test("charges the microphone opening to a stage of its own")
    func measuresTheOpening() async {
        let metrics = RecordingMetricsRecorder()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(),
            cleaner: FakeTranscriptCleaner(answering: tidiedAnswer),
            context: FakeContextEngine(context: .fixture()),
            inserter: FakeTextInserter(), metrics: metrics, clock: ManualClock())

        await pipeline.startRecording()

        #expect(await metrics.measurements.contains { $0.stage == .microphoneOpen })
        // The recording has not ended, so the stage that measures its ending has nothing yet.
        #expect(await metrics.measurements.contains { $0.stage == .capture } == false)
    }

    @Test("describes each finished recording's audio to the metrics, once")
    func measuresTheRecordingsQuality() async throws {
        let metrics = RecordingMetricsRecorder()
        let holes = CaptureGaps(holes: 1, milliseconds: 21, lostBuffers: 1)
        let silent = AudioSamples.silence(seconds: 1)
        let recording = AudioSamples.canonical(silent.samples, gaps: holes)
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(recording)),
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: spoken))),
            cleaner: FakeTranscriptCleaner(answering: tidiedAnswer),
            context: FakeContextEngine(context: .fixture()),
            inserter: FakeTextInserter(), metrics: metrics, clock: ManualClock())

        await pipeline.startRecording()
        await pipeline.finishRecording()

        let expected = try #require(
            CaptureQuality.measure(samples: recording.samples, sampleRate: recording.sampleRate, gaps: holes))
        #expect(await metrics.captureQualities == [expected])
    }

    @Test("tells the metrics when the chosen input was missing for the recording")
    func reportsAMissingChosenInput() async {
        let metrics = RecordingMetricsRecorder()
        let silent = AudioSamples.silence(seconds: 1)
        let recording = AudioSamples.canonical(silent.samples, chosenInputMissing: true)
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(recording)),
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: spoken))),
            cleaner: FakeTranscriptCleaner(answering: tidiedAnswer),
            context: FakeContextEngine(context: .fixture()),
            inserter: FakeTextInserter(), metrics: metrics, clock: ManualClock())

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await metrics.captureQualities.map(\.chosenInputMissing) == [true])
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

    @Test("a transcription error after a cancel does not replace idle with a stale failure")
    func failedTranscriptionAfterCancelRests() async {
        let gate = Gate()
        let speech = GatedSpeechEngine(gate: gate, error: .transcriptionFailed(description: "boom"))
        let pipeline = makePipeline(speech: speech)
        await pipeline.startRecording()
        let dictation = Task { await pipeline.finishRecording() }
        await gate.waitUntilReached()

        await pipeline.cancel()
        await gate.open()
        await dictation.value

        #expect(await pipeline.currentState == .idle)
    }

    @Test("the same transcription error is still reported when nobody cancelled")
    func failedTranscriptionWithoutCancelFails() async {
        let gate = Gate()
        let speech = GatedSpeechEngine(gate: gate, error: .transcriptionFailed(description: "boom"))
        let pipeline = makePipeline(speech: speech)
        await pipeline.startRecording()
        let dictation = Task { await pipeline.finishRecording() }
        await gate.waitUntilReached()

        await gate.open()
        await dictation.value

        guard case .failed = await pipeline.currentState else {
            Issue.record("expected a failure, got \(await pipeline.currentState)")
            return
        }
    }

    @Test("ignores a start that arrives while it is tidying")
    func startWhileTidyingIsIgnored() async {
        let capture = FakeAudioCaptureEngine()
        let gate = Gate()
        let pipeline = makePipeline(
            capture: capture,
            cleaner: FakeTranscriptCleaner(answering: tidiedAnswer, holding: { await gate.pass() }))
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

    @Test("refuses a dictation the microphone is not granted for, and says where to grant it")
    func startWithoutMicrophoneAccessOffersTheMicrophonePane() async {
        let capture = FakeAudioCaptureEngine(startOutcome: .failure(.microphoneDenied))
        let pipeline = makePipeline(capture: capture)

        await pipeline.startRecording()

        guard case .failed(let refusal) = await pipeline.currentState else {
            Issue.record("expected the dictation to fail, got \(await pipeline.currentState)")
            return
        }
        // The same sentence onboarding shows, so a refusal reads the same wherever it is met.
        #expect(refusal.message == PermissionError.microphoneDenied.userMessage)
        #expect(refusal.recovery == .openSystemSettings(.microphone))
        #expect(refusal.severity == .blocking)
    }

    @Test("does nothing when asked to finish while it is not recording")
    func finishWhenNotRecordingIsIgnored() async {
        let capture = FakeAudioCaptureEngine()
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(capture: capture, inserter: inserter)

        await pipeline.finishRecording()

        #expect(await pipeline.currentState == .idle)
        #expect(await capture.calls.isEmpty, "there was no recording to stop")
        #expect(inserter.received.isEmpty)
    }

    @Test("does not run a second time when a finished dictation is finished again")
    func finishAfterInsertionIsIgnored() async {
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(inserter: inserter)
        await pipeline.startRecording()
        await pipeline.finishRecording()

        await pipeline.finishRecording()

        #expect(inserter.received == [tidied])
    }

    @Test("passes through transcribing, then tidying, then inserting, then inserted")
    func happyPathVisitsEveryStageInOrder() async {
        let pipeline = makePipeline()
        let states = await pipeline.states()

        await pipeline.startRecording()
        await pipeline.finishRecording()

        let inserted = DictationOutcome(
            text: tidied, method: .accessibility, cleanedBy: .foundationModels,
            insertedInto: "Slack", insertedIntoIdentifier: "com.tinyspeck.slackmacgap",
            spokenFor: .zero, changes: AppliedChanges(spokenWords: 10, heard: spoken))
        // Inserting is its own state because the application takes its own time to show the words.
        #expect(
            await next(6, from: states) == [
                .idle, .recording, .transcribing, .tidying, .inserting(into: "Slack"), .inserted(inserted),
            ])
    }

    /// #222: the confirmation's answer used to reach the log and stop there, so nothing above could draw it.
    @Test("the finished dictation carries whether the words were seen to arrive")
    func outcomeCarriesTheArrival() async {
        let pipeline = makePipeline(
            inserter: FakeTextInserter(.success(InsertionAttempt(.pasteboard, arrival: .unconfirmed))))

        await pipeline.startRecording()
        await pipeline.finishRecording()

        guard case .inserted(let outcome) = await pipeline.currentState else {
            Issue.record("expected the dictation to finish")
            return
        }
        #expect(outcome.arrival == .unconfirmed)
    }

    /// Taken from the tidying context, since a fresh read at insertion time would name the wrong app.
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

    /// The name labels the row; the identifier is what its icon is looked up by.
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
        let cleaner = FakeTranscriptCleaner(answering: tidiedAnswer)
        let inserter = FakeTextInserter()
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

    @Test("asks the recogniser to warm as the recording starts")
    func startRecordingWarmsTheRecogniser() async {
        let speech = FakeSpeechEngine()
        let pipeline = makePipeline(speech: speech)

        await pipeline.startRecording()

        #expect(await speech.warmCalls.count == 1)
        #expect(await pipeline.currentState == .recording)
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

    /// Saying nothing is not an error, and a failure for it would be something to dismiss.
    @Test("returns quietly to idle when nothing was said")
    func silenceEndsQuietly() async {
        let cleaner = FakeTranscriptCleaner(answering: tidiedAnswer)
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: "   "))),
            cleaner: cleaner,
            inserter: inserter
        )
        let states = await pipeline.states()

        await pipeline.startRecording()
        await pipeline.finishRecording()

        // Not `.idle`: returning quietly is indistinguishable from the app being broken.
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

    /// `prepare` stays non-throwing so launch code decides nothing, but the failure must reach the screen.
    @Test("shows the failure when the recogniser will not start")
    func prepareFailureReachesTheInterface() async {
        let speech = FakeSpeechEngine(prepareOutcome: .failure(.modelNotInstalled))
        let pipeline = makePipeline(speech: speech)

        await pipeline.prepare()

        #expect(
            await pipeline.currentState
                == .failed(
                    DictationFailure(SpeechEngineError.modelNotInstalled, speechEngineKind: .whisperKit)),
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

    /// Loading the model behind a running dictation must not overwrite where it has got to.
    @Test("leaves a dictation under way alone when asked to prepare")
    func prepareWhileBusyIsIgnored() async {
        let speech = FakeSpeechEngine(prepareOutcome: .failure(.modelNotInstalled))
        let pipeline = makePipeline(speech: speech)
        await pipeline.startRecording()

        await pipeline.prepare()

        #expect(await pipeline.currentState == .recording)
    }

    /// A tap too brief to transcribe is told how to fix it, rather than that nothing was heard.
    @Test("says a hold was too short when the whole recording was")
    func tooShortSaysSo() async {
        let briefSpeech = AudioSamples.canonical(
            Array(repeating: Float(0.1), count: AudioSamples.canonicalSampleRate / 5))
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(briefSpeech)),
            speech: FakeSpeechEngine(transcribeOutcome: .failure(.audioTooShort)))

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(
            await pipeline.currentState
                == .failed(DictationFailure(SpeechEngineError.audioTooShort, speechEngineKind: .whisperKit)))
    }

    /// "um" tidies to nothing, and inserting nothing over a selection deletes it.
    @Test(
        "inserts nothing when tidying leaves nothing, rather than deleting the selection",
        arguments: ["", "   ", ".", "…"])
    func tidyingToNothingInsertsNothing(tidiedAway: String) async {
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: "um"))),
            cleaner: FakeTranscriptCleaner(
                answering: ScriptedSequence(
                    .success(TransformationResult(text: tidiedAway, producedBy: .rules)))),
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

    @Test(
        "names a muted input apart from a quiet room when nothing is heard",
        arguments: [
            (AudioSamples.silence(seconds: 3), SpeechEngineError.noSignal),
            (.roomTone(seconds: 3), .nothingHeard),
        ])
    func mutedInputIsNamed(recorded: AudioSamples, expected: SpeechEngineError) async {
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(recorded)),
            speech: FakeSpeechEngine(transcribeOutcome: .failure(.nothingHeard)))

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await pipeline.currentState == .failed(DictationFailure(expected)))
    }

    /// The menu bar's Start Dictation can race the hotkey; only one may open the microphone.
    @Test("opens the microphone once when two presses arrive together")
    func overlappingStartsOpenTheMicrophoneOnce() async {
        // Holds only the first arrival, so the racing press runs to a conclusion the test can look at.
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

    @Test("a microphone error after a cancel does not replace idle with a stale failure")
    func failedOpenAfterCancelRests() async {
        let gate = Gate()
        let capture = GatedCaptureEngine(gate: gate, startError: .engineFailed(description: "denied"))
        let pipeline = makePipeline(capture: capture)

        let start = Task { await pipeline.startRecording() }
        await gate.waitUntilReached()
        await pipeline.cancel()
        await gate.open()
        await start.value

        #expect(
            await pipeline.currentState == .idle,
            "the cancel already settled the pipeline; the abandoned attempt's error must not overwrite it")

        // The scripted error is consumed by the first throw, so this call opens for real.
        await pipeline.startRecording()
        #expect(
            await pipeline.currentState == .recording,
            "a later dictation must still be able to start after the cancelled attempt settled")
    }

    @Test("the same open failure is still reported when nobody cancelled")
    func openFailureWithoutACancelStillFails() async {
        let capture = FakeAudioCaptureEngine(
            startOutcome: .failure(.engineFailed(description: "denied")))
        let pipeline = makePipeline(capture: capture)

        await pipeline.startRecording()

        #expect(
            await pipeline.currentState
                == .failed(DictationFailure(AudioCaptureError.engineFailed(description: "denied"))),
            "a genuine microphone-open error must still be reported when nobody cancelled")
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
