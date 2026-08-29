import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// A ``HotkeyMonitoring`` that records how it was started and stopped, can refuse to
/// start, and lets a test push presses and releases through its stream.
///
/// Named for this file so it can sit beside the other pipeline test files' doubles in
/// one test target.
private final class FakeHotkeyMonitor: HotkeyMonitoring {
    private struct State: Sendable {
        var startOutcome: ScriptedOutcome<Void, HotkeyError>
        var bindings: [HotkeyBinding] = []
        var stops = 0
    }

    private let state: Mutex<State>
    private let stream: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation

    init(startOutcome: ScriptedOutcome<Void, HotkeyError> = .ok) {
        self.state = Mutex(State(startOutcome: startOutcome))
        let (stream, continuation) = AsyncStream<HotkeyEvent>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    @MainActor func start(binding: HotkeyBinding) throws(HotkeyError) {
        let outcome = state.withLock { state -> ScriptedOutcome<Void, HotkeyError> in
            state.bindings.append(binding)
            return state.startOutcome
        }
        try outcome.resolve()
    }

    func stop() {
        state.withLock { $0.stops += 1 }
    }

    var events: AsyncStream<HotkeyEvent> { stream }

    /// Pushes an event as the real monitor would when the user works the shortcut.
    func emit(_ event: HotkeyEvent) {
        continuation.yield(event)
    }

    /// Every binding the controller asked to watch, in order.
    var bindings: [HotkeyBinding] { state.withLock { $0.bindings } }
    var stops: Int { state.withLock { $0.stops } }
}

/// A ``RecordingCueing`` that records the sounds it was asked to play, in order.
private final class SpyCue: RecordingCueing {
    enum Play: Sendable, Equatable {
        case start
        case stop
    }

    private let log = Mutex<[Play]>([])

    func playStart() {
        log.withLock { $0.append(.start) }
    }

    func playStop() {
        log.withLock { $0.append(.stop) }
    }

    var plays: [Play] { log.withLock { $0 } }
}

/// A ``TranscriptCleaning`` that always tidies to the same sentence.
private final class ControllerCleaner: TranscriptCleaning {
    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        TransformationResult(text: controllerTidied, producedBy: .foundationModels)
    }
}

/// A ``TextInserting`` that records every string it was handed.
private final class ControllerInserter: TextInserting {
    private let log = Mutex<[String]>([])

    func insert(_ text: String) async throws(TextInsertionError) -> TextInsertionMethod {
        log.withLock { $0.append(text) }
        return .accessibility
    }

    /// Everything that reached the user's document, in order.
    var received: [String] { log.withLock { $0 } }
}

// MARK: - Fixtures

private let controllerSpoken = "um i'll be about twenty minutes late to the meeting"
private let controllerTidied = "I'll be about twenty minutes late to the meeting."

private let controllerOutcome = DictationOutcome(
    text: controllerTidied, method: .accessibility, cleanedBy: .foundationModels,
    insertedInto: "Slack", insertedIntoIdentifier: "com.tinyspeck.slackmacgap",
    spokenFor: .zero,
    changes: AppliedChanges(spokenWords: 10))

/// A binding that is nobody's default, so a test can tell it apart from one the
/// controller might have supplied itself.
private let controllerBinding = HotkeyBinding(keyCode: 40, modifiers: [.control, .shift])

// MARK: - Harness

/// Everything one controller was built from, so a test can look at any of it.
private struct ControllerHarness {
    let controller: DictationController<ManualClock>
    let pipeline: DictationPipeline
    let monitor: FakeHotkeyMonitor
    let cue: SpyCue
    let capture: FakeAudioCaptureEngine
    let speech: FakeSpeechEngine
    let inserter: ControllerInserter
    let clock: ManualClock
}

private func makeHarness(
    activation: HotkeyActivation = .holdToTalk,
    captureStart: ScriptedOutcome<Void, AudioCaptureError> = .ok,
    monitorStart: ScriptedOutcome<Void, HotkeyError> = .ok
) -> ControllerHarness {
    let capture = FakeAudioCaptureEngine(startOutcome: captureStart)
    let speech = FakeSpeechEngine(
        transcribeOutcome: .success(.fixture(text: controllerSpoken)))
    let inserter = ControllerInserter()
    let pipeline = DictationPipeline(
        capture: capture,
        speech: speech,
        cleaner: ControllerCleaner(),
        context: FakeContextEngine(context: .fixture()),
        inserter: inserter,
        // A clock of its own, so the stages cannot move the one the hold is measured on.
        clock: ManualClock()
    )
    let monitor = FakeHotkeyMonitor(startOutcome: monitorStart)
    let cue = SpyCue()
    let clock = ManualClock()
    return ControllerHarness(
        controller: DictationController(
            pipeline: pipeline,
            monitor: monitor,
            cue: cue,
            activation: activation,
            clock: clock
        ),
        pipeline: pipeline,
        monitor: monitor,
        cue: cue,
        capture: capture,
        speech: speech,
        inserter: inserter,
        clock: clock
    )
}

/// Just short of, exactly at, and just past the line between a slip and a dictation.
private let justUnderTheMinimum = DictationController<ManualClock>.minimumHold - .milliseconds(1)
private let exactlyTheMinimum = DictationController<ManualClock>.minimumHold
private let justOverTheMinimum = DictationController<ManualClock>.minimumHold + .milliseconds(1)

// MARK: - Tests

@Suite("Dictation controller: turning key presses into dictations")
struct DictationControllerTests {

    // MARK: Watching for the shortcut

    @Test("starts watching for exactly the binding it was given")
    func startWatchesTheGivenBinding() async throws {
        let harness = makeHarness()

        try await harness.controller.start(binding: controllerBinding)

        #expect(harness.monitor.bindings == [controllerBinding])

        await harness.controller.stop()
    }

    @Test("stops watching when it is stopped")
    func stopStopsTheMonitor() async throws {
        let harness = makeHarness()
        try await harness.controller.start(binding: controllerBinding)

        await harness.controller.stop()

        #expect(harness.monitor.stops == 1)
    }

    @Test("reports the refusal when macOS will not let it watch for keys")
    func startPropagatesTheAccessibilityRefusal() async {
        let harness = makeHarness(monitorStart: .failure(.observationNotPermitted))

        await #expect(throws: HotkeyError.observationNotPermitted) {
            try await harness.controller.start(binding: controllerBinding)
        }
    }

    @Test("holds to talk unless it is told otherwise")
    func defaultActivationIsHoldToTalk() async {
        let controller = DictationController(
            pipeline: DictationPipeline(
                capture: FakeAudioCaptureEngine(),
                speech: FakeSpeechEngine(),
                cleaner: ControllerCleaner(),
                context: FakeContextEngine(context: .fixture()),
                inserter: ControllerInserter(),
                clock: ManualClock()
            ),
            monitor: FakeHotkeyMonitor(),
            clock: ManualClock()
        )

        #expect(await controller.currentActivation == .holdToTalk)
    }

    // MARK: Hold to talk

    @Test("begins recording while the shortcut is held down")
    func pressBeginsRecording() async {
        let harness = makeHarness()

        await harness.controller.handle(.pressed)

        #expect(await harness.pipeline.currentState == .recording)
        #expect(await harness.capture.calls.events == [.start])
    }

    @Test("inserts what was said when a long-enough hold is released")
    func releaseAfterALongEnoughHoldInsertsTheWords() async {
        let harness = makeHarness()
        await harness.controller.handle(.pressed)
        harness.clock.advance(by: .seconds(3))

        await harness.controller.handle(.released)

        #expect(harness.inserter.received == [controllerTidied])
        #expect(await harness.pipeline.currentState == .inserted(controllerOutcome))
    }

    /// An accidental tap must not tell the user their speech was too short for
    /// something they never meant to do.
    @Test("cancels without a word when the shortcut is only tapped by accident")
    func aHoldShorterThanTheMinimumIsASlip() async {
        let harness = makeHarness()
        await harness.controller.handle(.pressed)
        harness.clock.advance(by: justUnderTheMinimum)

        await harness.controller.handle(.released)

        #expect(await harness.pipeline.currentState == .idle, "a slip is not a failure")
        #expect(await harness.speech.transcribeCalls.isEmpty)
        #expect(harness.inserter.received.isEmpty)
        #expect(await harness.capture.calls.events == [.start, .cancel])
    }

    @Test("treats a hold of exactly the minimum as a dictation rather than a slip")
    func aHoldOfExactlyTheMinimumIsADictation() async {
        let harness = makeHarness()
        await harness.controller.handle(.pressed)
        harness.clock.advance(by: exactlyTheMinimum)

        await harness.controller.handle(.released)

        #expect(harness.inserter.received == [controllerTidied])
    }

    @Test("treats a hold just past the minimum as a dictation")
    func aHoldJustOverTheMinimumIsADictation() async {
        let harness = makeHarness()
        await harness.controller.handle(.pressed)
        harness.clock.advance(by: justOverTheMinimum)

        await harness.controller.handle(.released)

        #expect(harness.inserter.received == [controllerTidied])
    }

    @Test("does nothing when the shortcut is released without having been held")
    func releaseWithoutRecordingDoesNothing() async {
        let harness = makeHarness()

        await harness.controller.handle(.released)

        #expect(await harness.pipeline.currentState == .idle)
        #expect(await harness.capture.calls.isEmpty)
        #expect(harness.cue.plays.isEmpty)
        #expect(harness.inserter.received.isEmpty)
    }

    // MARK: Press to toggle

    @Test("starts on the first press and finishes on the second when set to toggle")
    func toggleStartsThenFinishes() async {
        let harness = makeHarness(activation: .pressToToggle)

        await harness.controller.handle(.pressed)
        #expect(await harness.pipeline.currentState == .recording)

        await harness.controller.handle(.pressed)
        #expect(harness.inserter.received == [controllerTidied])
        #expect(await harness.pipeline.currentState == .inserted(controllerOutcome))
    }

    @Test("ignores the release between the two presses when set to toggle")
    func toggleIgnoresTheReleaseBetweenPresses() async {
        let harness = makeHarness(activation: .pressToToggle)
        await harness.controller.handle(.pressed)

        await harness.controller.handle(.released)

        #expect(await harness.pipeline.currentState == .recording, "the next press is what stops it")
        #expect(harness.inserter.received.isEmpty)
        #expect(await harness.capture.calls.events == [.start])
    }

    @Test("changes the way it is activated while it is running")
    func activationCanBeChangedAtRuntime() async {
        let harness = makeHarness(activation: .holdToTalk)

        await harness.controller.setActivation(.pressToToggle)
        #expect(await harness.controller.currentActivation == .pressToToggle)

        await harness.controller.handle(.pressed)
        await harness.controller.handle(.released)
        #expect(
            await harness.pipeline.currentState == .recording,
            "the new mode must take effect at once, so releasing no longer finishes")

        await harness.controller.handle(.pressed)
        #expect(harness.inserter.received == [controllerTidied])
    }

    // MARK: The cue

    @Test("plays the start sound once the microphone is really live")
    func startSoundPlaysWhenListening() async {
        let harness = makeHarness()

        await harness.controller.handle(.pressed)

        #expect(harness.cue.plays == [.start])
    }

    /// A sound on a failed start would tell the user everything was fine when it was
    /// not: they would speak into a microphone that never opened.
    @Test("stays silent when the microphone refuses to open")
    func noStartSoundWhenTheMicrophoneRefuses() async {
        let harness = makeHarness(captureStart: .failure(.noInputDevice))

        await harness.controller.handle(.pressed)

        let refusal = DictationFailure(AudioCaptureError.noInputDevice)
        #expect(await harness.pipeline.currentState == .failed(refusal))
        #expect(harness.cue.plays.isEmpty)
    }

    @Test("plays the stop sound when a hold finishes normally")
    func stopSoundPlaysWhenAHoldFinishes() async {
        let harness = makeHarness()
        await harness.controller.handle(.pressed)
        harness.clock.advance(by: .seconds(3))

        await harness.controller.handle(.released)

        #expect(harness.cue.plays == [.start, .stop])
    }

    @Test("does not play the stop sound when a slip cancels the recording")
    func noStopSoundWhenASlipCancels() async {
        let harness = makeHarness()
        await harness.controller.handle(.pressed)
        harness.clock.advance(by: justUnderTheMinimum)

        await harness.controller.handle(.released)

        #expect(harness.cue.plays == [.start], "nothing finished, so nothing announces it")
    }

    @Test("plays the stop sound on the closing press when set to toggle")
    func stopSoundPlaysOnTheClosingPress() async {
        let harness = makeHarness(activation: .pressToToggle)
        await harness.controller.handle(.pressed)

        await harness.controller.handle(.pressed)

        #expect(harness.cue.plays == [.start, .stop])
    }
}

/// Rebinding, which is what changing the shortcut in Settings does.
@Suite("Changing the shortcut while it is running")
struct DictationControllerRebindTests {
    /// Until this, `start` had exactly one caller — at launch — so rebinding was never
    /// exercised at all: changing the shortcut in Settings relabelled every screen and
    /// left the old key in force until the next launch.
    ///
    /// What this does NOT cover: `start` also used to overwrite `forwardingTask` without
    /// cancelling it, which left two tasks draining one `AsyncStream` and split presses
    /// between them. That is fixed in `start`, but it cannot be asserted here — driving
    /// the monitor's stream through this harness is not deterministic, and a test that
    /// passes about half the time is worse than none. The cancellation is one line, above
    /// the code it guards, with the reason written beside it.
    @Test("rebinds the monitor rather than ignoring the new shortcut")
    func rebindReachesTheMonitor() async throws {
        let harness = makeHarness()
        let second = HotkeyBinding(keyCode: 2, modifiers: [.control, .option])

        try await harness.controller.start(binding: .optionSpace)
        try await harness.controller.start(binding: second)

        #expect(harness.monitor.bindings == [.optionSpace, second])
    }
}

/// Starting a dictation from something clicked rather than something held.
@Suite("Dictating from a control")
struct DictationControllerControlTests {
    /// Both of these were live. The Quick Panel's microphone button sent `.pressed` and
    /// `.released` together, which in hold-to-talk measures shorter than the slip
    /// threshold and cancels the recording it just began — the button could never produce
    /// a dictation at all. "Try Again" sent `.pressed` alone, which opened the microphone
    /// with nothing able to close it.
    @Test("a click starts a dictation and a second click finishes it, in hold-to-talk")
    func controlTogglesEvenWhenTheShortcutIsAHold() async {
        let harness = makeHarness(activation: .holdToTalk)

        await harness.controller.toggleFromControl()
        #expect(
            await harness.pipeline.currentState == .recording,
            "a click has no release, so it must not be measured as a hold")

        await harness.controller.toggleFromControl()
        #expect(harness.inserter.received == [controllerTidied], "the second click finished it")
        #expect(await harness.capture.calls.events == [.start, .stop], "stopped, not cancelled")
    }

    @Test("clicking twice does not start a second dictation over the first")
    func controlDoesNotStack() async {
        let harness = makeHarness(activation: .holdToTalk)

        await harness.controller.toggleFromControl()
        await harness.controller.toggleFromControl()
        await harness.controller.toggleFromControl()

        // start, stop, start — never two starts in a row.
        #expect(await harness.capture.calls.events == [.start, .stop, .start])
    }

    @Test("the cue sounds for a control, as it does for the shortcut")
    func controlPlaysTheCue() async {
        let harness = makeHarness(activation: .holdToTalk)
        await harness.controller.toggleFromControl()
        #expect(harness.cue.plays == [.start])
        await harness.controller.toggleFromControl()
        #expect(harness.cue.plays == [.start, .stop])
    }
}
