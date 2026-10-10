// Tests how key presses and clicks become dictations.
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// A ``HotkeyMonitoring`` that records its starts and stops, can refuse, and takes pushed gestures.
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

/// A ``RecordingCueing`` that records the sounds it is asked to play, in order.
private final class SpyCue: RecordingCueing {
    enum Play: Sendable, Equatable {
        case start
        case stop
        case warning
        case discarded
    }

    private let log = Mutex<[Play]>([])

    func playStart() {
        log.withLock { $0.append(.start) }
    }

    func playStop() {
        log.withLock { $0.append(.stop) }
    }

    func playWarning() {
        log.withLock { $0.append(.warning) }
    }

    func playDiscarded() {
        log.withLock { $0.append(.discarded) }
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

/// A ``TextInserting`` that records every string it is handed.
private final class ControllerInserter: TextInserting {
    private let log = Mutex<[String]>([])

    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        log.withLock { $0.append(text) }
        return InsertionAttempt(.accessibility)
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
    changes: AppliedChanges(spokenWords: 10, heard: controllerSpoken))

/// A binding that is nobody's default, so a test can tell it from one the controller supplies.
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

/// Counts the near-miss taps the controller reports.
private final class NearMissSpy: Sendable {
    private let log = Mutex(0)

    func record() { log.withLock { $0 += 1 } }

    var count: Int { log.withLock { $0 } }
}

/// Records every ``StopGesture`` the controller reports, so a test can watch a live transition.
private final class StopGestureSpy: Sendable {
    private let log = Mutex<[StopGesture]>([])

    /// The closure handed to ``DictationController/init``, so a test can wire it in.
    func record(_ gesture: StopGesture) {
        log.withLock { $0.append(gesture) }
    }

    /// Every gesture the controller reported, in order.
    var recorded: [StopGesture] { log.withLock { $0 } }
}

private func makeHarness(
    activation: HotkeyActivation = .holdToTalk,
    handsFreeEnabled: Bool = true,
    doubleTapWindow: Duration = .milliseconds(450),
    minimumHold: Duration = DictationController<ManualClock>.minimumHold,
    releaseGrace: Duration = .zero,
    nearMisses: NearMissSpy = NearMissSpy(),
    captureStart: ScriptedOutcome<Void, AudioCaptureError> = .ok,
    monitorStart: ScriptedOutcome<Void, HotkeyError> = .ok,
    gestureSpy: StopGestureSpy = StopGestureSpy()
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
            handsFreeEnabled: handsFreeEnabled,
            doubleTapWindow: doubleTapWindow,
            minimumHold: minimumHold,
            releaseGrace: releaseGrace,
            clock: clock,
            onNearMissTap: { nearMisses.record() },
            onStopGestureChange: { gesture in gestureSpy.record(gesture) }
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

/// One tap: pressed and released inside the slip threshold, which is half of a double tap.
private func tap(_ harness: ControllerHarness) async {
    await harness.controller.handle(.pressed)
    harness.clock.advance(by: justUnderTheMinimum)
    await harness.controller.handle(.released)
}

private let exactlyTheMinimum = DictationController<ManualClock>.minimumHold
private let justOverTheMinimum = DictationController<ManualClock>.minimumHold + .milliseconds(1)

// MARK: - Tests

@Suite("Dictation controller: turning key presses into dictations")
struct DictationControllerTests {

    @Test("a hold keeps listening for the release grace after the key comes up, then dictates")
    func holdKeepsListeningThroughReleaseGrace() async {
        let grace = DictationController<ManualClock>.releaseGrace
        let harness = makeHarness(releaseGrace: grace)
        await harness.controller.handle(.pressed)
        harness.clock.advance(by: justOverTheMinimum)
        let release = Task { await harness.controller.handle(.released) }

        while !harness.clock.advanceIfSomethingIsWaiting(exactly: grace) { await Task.yield() }
        await release.value

        #expect(!(await harness.pipeline.currentState.isListening))
        #expect(harness.inserter.received == [controllerTidied])
    }

    @Test("press-to-toggle stops at once, with no release grace")
    func toggleHasNoReleaseGrace() async {
        let harness = makeHarness(
            activation: .pressToToggle, releaseGrace: DictationController<ManualClock>.releaseGrace)
        await harness.controller.handle(.pressed)
        await harness.controller.handle(.released)
        await harness.controller.handle(.pressed)

        #expect(!(await harness.pipeline.currentState.isListening))
        #expect(harness.inserter.received == [controllerTidied])
    }

    @Test("a slip discards at once, with no release grace")
    func slipHasNoReleaseGrace() async {
        let harness = makeHarness(
            handsFreeEnabled: false, releaseGrace: DictationController<ManualClock>.releaseGrace)
        await tap(harness)

        #expect(!(await harness.pipeline.currentState.isListening))
        #expect(harness.inserter.received.isEmpty)
    }

    @Test("session loss finishes a toggle dictation and preserves its words")
    func sessionLossFinishesToggle() async {
        let harness = makeHarness(activation: .pressToToggle)
        await harness.controller.handle(.pressed)
        #expect(await harness.pipeline.currentState.isListening)

        await harness.controller.endForSessionEnding()

        #expect(!(await harness.pipeline.currentState.isListening))
        #expect(harness.inserter.received == [controllerTidied])
        #expect(await harness.controller.currentStopGesture == .pressAgain)
    }

    @Test("sleep finishes a toggle dictation before the session is suspended")
    func sleepFinishesToggle() async {
        let harness = makeHarness(activation: .pressToToggle)
        await harness.controller.handle(.pressed)
        await harness.controller.endForSessionEnding()

        #expect(!(await harness.pipeline.currentState.isListening))
        #expect(harness.inserter.received == [controllerTidied])
    }

    @Test("the first toggle press after a session end opens the microphone instead of closing it")
    func firstTogglePressAfterSessionEndStarts() async {
        let harness = makeHarness(activation: .pressToToggle)
        await harness.controller.handle(.pressed)
        await harness.controller.endForSessionEnding()

        await harness.controller.handle(.pressed)
        #expect(await harness.pipeline.currentState.isListening)
        await harness.controller.handle(.pressed)

        #expect(harness.inserter.received == [controllerTidied, controllerTidied])
    }

    @Test("a hold cut by a session end ignores its late release, and the next hold dictates")
    func holdCutBySessionEndThenNextHold() async {
        let harness = makeHarness()
        await harness.controller.handle(.pressed)
        harness.clock.advance(by: justOverTheMinimum)
        await harness.controller.endForSessionEnding()
        #expect(harness.inserter.received == [controllerTidied])

        harness.clock.advance(by: .seconds(3600))
        await harness.controller.handle(.released)
        #expect(!(await harness.pipeline.currentState.isListening))
        #expect(harness.inserter.received == [controllerTidied], "the late release inserts nothing")

        await harness.controller.handle(.pressed)
        harness.clock.advance(by: justOverTheMinimum)
        await harness.controller.handle(.released)

        #expect(harness.inserter.received == [controllerTidied, controllerTidied])
    }

    @Test("a hands-free dictation cut by a session end leaves the next hold an ordinary hold")
    func handsFreeCutBySessionEndThenNextHold() async {
        let harness = makeHarness()
        await tap(harness)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)
        #expect(await harness.pipeline.currentState.isListening)
        await harness.controller.endForSessionEnding()

        harness.clock.advance(by: .seconds(3600))
        await harness.controller.handle(.pressed)
        #expect(await harness.pipeline.currentState.isListening)
        harness.clock.advance(by: justOverTheMinimum)
        await harness.controller.handle(.released)

        #expect(!(await harness.pipeline.currentState.isListening))
        #expect(harness.inserter.received == [controllerTidied, controllerTidied])
    }

    @Test("a session end with nothing recording changes nothing for the next dictation")
    func idleSessionEndThenDictation() async {
        let harness = makeHarness(activation: .pressToToggle)
        await harness.controller.endForSessionEnding()
        await harness.controller.endForSessionEnding()

        await harness.controller.handle(.pressed)
        await harness.controller.handle(.pressed)

        #expect(harness.inserter.received == [controllerTidied])
    }

    @Test("stopping while a dictation is recording finishes it and closes the microphone")
    func stopFinishesARecordingDictation() async throws {
        let harness = makeHarness(activation: .pressToToggle)
        try await harness.controller.start(binding: controllerBinding)
        await harness.controller.handle(.pressed)
        #expect(await harness.pipeline.currentState.isListening)

        await harness.controller.stop()

        #expect(!(await harness.pipeline.currentState.isListening))
        #expect(harness.inserter.received == [controllerTidied])
        #expect(harness.monitor.stops == 1)
    }

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

    // MARK: Double tap, which leaves the microphone open

    /// Two taps on the dictation key mean "keep listening", so nothing has to be held down.
    @Test("a double tap leaves the microphone open")
    func doubleTapGoesHandsFree() async {
        let harness = makeHarness()
        await tap(harness)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)

        #expect(
            await harness.pipeline.currentState.isListening,
            "the second tap keeps the microphone open rather than cancelling")
        #expect(harness.inserter.received.isEmpty, "nothing is inserted until it is stopped")
    }

    @Test("another double tap is what closes it")
    func secondDoubleTapStops() async {
        let harness = makeHarness()
        await tap(harness)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)

        harness.clock.advance(by: .seconds(4))
        await tap(harness)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)

        #expect(await harness.pipeline.currentState.isListening == false)
        #expect(harness.inserter.received == [controllerTidied])
    }

    @Test("with hands-free switched off, a double tap is two slips")
    func doubleTapWithHandsFreeOffIsTwoSlips() async {
        let harness = makeHarness(handsFreeEnabled: false)
        await tap(harness)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)

        #expect(await harness.pipeline.currentState.isListening == false)
        #expect(harness.inserter.received.isEmpty, "a slip inserts nothing")
    }

    @Test("with hands-free switched off, a modifier-only double tap opens nothing")
    func modifierDoubleTapWithHandsFreeOffOpensNothing() async throws {
        let harness = makeHarness(handsFreeEnabled: false)
        try await harness.controller.start(
            binding: HotkeyBinding(keyCode: 58, modifiers: [.option, .command, .control]))
        await tap(harness)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)

        #expect(await harness.pipeline.currentState.isListening == false)
        await harness.controller.stop()
    }

    @Test("switching hands-free off finishes a double-tap dictation and keeps its words")
    func switchingHandsFreeOffFinishesIt() async {
        let harness = makeHarness()
        await tap(harness)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)
        #expect(await harness.pipeline.currentState.isListening)

        await harness.controller.setHandsFreeEnabled(false)

        #expect(await harness.pipeline.currentState.isListening == false)
        #expect(harness.inserter.received == [controllerTidied])
        #expect(await harness.controller.isHandsFreeEnabled == false)
    }

    @Test("switching hands-free back on lets the next double tap open the microphone")
    func switchingHandsFreeBackOnWorks() async {
        let harness = makeHarness(handsFreeEnabled: false)
        await harness.controller.setHandsFreeEnabled(false)
        await harness.controller.setHandsFreeEnabled(true)
        await tap(harness)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)

        #expect(await harness.pipeline.currentState.isListening)
    }

    @Test("switching hands-free off leaves a held dictation alone")
    func switchingHandsFreeOffLeavesAHold() async {
        let harness = makeHarness()
        await harness.controller.handle(.pressed)
        await harness.controller.setHandsFreeEnabled(false)

        #expect(await harness.pipeline.currentState.isListening, "a hold is not hands-free")
        harness.clock.advance(by: .seconds(3))
        await harness.controller.handle(.released)
        #expect(harness.inserter.received == [controllerTidied])
    }

    /// Two taps far apart are two slips, which is what an accidental brush against the key is.
    @Test("taps too far apart stay two separate slips")
    func slowTapsAreNotAGesture() async {
        let harness = makeHarness()
        await tap(harness)
        harness.clock.advance(by: DictationController<ManualClock>.doubleTapWindow + .milliseconds(1))
        await tap(harness)

        #expect(await harness.pipeline.currentState == .idle, "neither tap started anything")
        #expect(harness.inserter.received.isEmpty)
    }

    @Test("a configured slower window recognizes taps 600 ms apart")
    func configuredSlowerDoubleTapWindow() async {
        let harness = makeHarness(doubleTapWindow: .milliseconds(800))
        await tap(harness)
        harness.clock.advance(by: .milliseconds(600))
        await tap(harness)

        #expect(await harness.pipeline.currentState.isListening)
        #expect(await harness.controller.currentStopGesture == .pressAgainHandsFree)
    }

    @Test("a lengthened hold length lets a slower press count as a tap")
    func configuredLongerHoldLength() async {
        let harness = makeHarness(minimumHold: .milliseconds(500))
        await harness.controller.handle(.pressed)
        harness.clock.advance(by: .milliseconds(400))
        await harness.controller.handle(.released)
        harness.clock.advance(by: .milliseconds(20))
        await harness.controller.handle(.pressed)
        harness.clock.advance(by: .milliseconds(400))
        await harness.controller.handle(.released)

        #expect(await harness.pipeline.currentState.isListening)
        #expect(await harness.controller.currentStopGesture == .pressAgainHandsFree)
    }

    @Test("changing the hold length takes effect on the next press")
    func setMinimumHoldTakesEffect() async {
        let harness = makeHarness()
        await harness.controller.setMinimumHold(.milliseconds(500))
        await harness.controller.handle(.pressed)
        harness.clock.advance(by: .milliseconds(400))
        await harness.controller.handle(.released)

        #expect(harness.inserter.received.isEmpty, "a 400 ms press is now a tap, not a dictation")
    }

    @Test("a second tap within twice the window is announced as a near miss")
    func nearMissTapIsReported() async {
        let nearMisses = NearMissSpy()
        let harness = makeHarness(nearMisses: nearMisses)
        await tap(harness)
        harness.clock.advance(by: .milliseconds(700))
        await tap(harness)

        #expect(nearMisses.count == 1)
        #expect(await harness.pipeline.currentState.isListening == false)
    }

    @Test("taps further apart than twice the window, or paired, are not near misses")
    func farOrPairedTapsAreNotNearMisses() async {
        let nearMisses = NearMissSpy()
        let harness = makeHarness(nearMisses: nearMisses)
        await tap(harness)
        harness.clock.advance(by: .milliseconds(900))
        await tap(harness)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)

        #expect(nearMisses.count == 0)
        #expect(await harness.pipeline.currentState.isListening)
    }

    @Test("with hands-free off, no tap is a near miss")
    func noNearMissWithHandsFreeOff() async {
        let nearMisses = NearMissSpy()
        let harness = makeHarness(handsFreeEnabled: false, nearMisses: nearMisses)
        await tap(harness)
        harness.clock.advance(by: .milliseconds(700))
        await tap(harness)

        #expect(nearMisses.count == 0)
    }

    /// A real hold must not become hands-free, or letting go would leave the microphone on.
    @Test("holding after a tap still ends when the key comes up")
    func aHoldAfterATapStillEnds() async {
        let harness = makeHarness()
        await tap(harness)
        harness.clock.advance(by: .milliseconds(120))

        await harness.controller.handle(.pressed)
        harness.clock.advance(by: .seconds(3))
        await harness.controller.handle(.released)

        #expect(await harness.pipeline.currentState.isListening == false)
        #expect(harness.inserter.received == [controllerTidied])
    }

    /// A finished hold between the two taps must not let them pair up as a double tap.
    @Test("a tap before a completed hold does not pair with a tap after it")
    func aTapBeforeAHoldDoesNotPairWithATapAfterIt() async {
        let harness = makeHarness()
        await tap(harness)

        await harness.controller.handle(.pressed)
        harness.clock.advance(by: .milliseconds(201))
        await harness.controller.handle(.released)

        await tap(harness)

        #expect(
            await harness.pipeline.currentState.isListening == false,
            "the hold's own tidy-up finished the dictation; the lone tap after it is only a slip")
        #expect(harness.inserter.received == [controllerTidied])
    }

    /// One stray tap while hands-free must not close the microphone on its own.
    @Test("a single tap while hands-free changes nothing")
    func oneTapDoesNotStopHandsFree() async {
        let harness = makeHarness()
        await tap(harness)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)

        harness.clock.advance(by: .seconds(2))
        await tap(harness)

        #expect(await harness.pipeline.currentState.isListening, "it takes two taps to stop")
        #expect(harness.inserter.received.isEmpty)
    }

    /// An accidental tap must not tell the user their speech was too short.
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

    /// A sound on a failed start would say everything is fine over a microphone that never opened.
    @Test("stays silent when the microphone refuses to open")
    func noStartSoundWhenTheMicrophoneRefuses() async {
        let harness = makeHarness(captureStart: .failure(.noInputDevice))

        await harness.controller.handle(.pressed)

        let refusal = DictationFailure(AudioCaptureError.noInputDevice)
        #expect(await harness.pipeline.currentState == .failed(refusal))
        #expect(harness.cue.plays.isEmpty)
    }

    /// The stop cue belongs to the capture engine, which alone knows when the microphone closed.
    @Test("leaves the stop sound to the microphone when a hold finishes, so it is never recorded")
    func stopSoundIsLeftToTheMicrophoneWhenAHoldFinishes() async {
        let harness = makeHarness()
        await harness.controller.handle(.pressed)
        harness.clock.advance(by: .seconds(3))

        await harness.controller.handle(.released)

        #expect(harness.cue.plays == [.start])
        #expect(await harness.capture.calls.events == [.start, .stop], "the microphone was stopped")
    }

    @Test("does not play the stop sound when a slip cancels the recording")
    func noStopSoundWhenASlipCancels() async {
        let harness = makeHarness()
        await harness.controller.handle(.pressed)
        harness.clock.advance(by: justUnderTheMinimum)

        await harness.controller.handle(.released)

        #expect(harness.cue.plays == [.start], "nothing finished, so nothing announces it")
    }

    @Test("leaves the stop sound to the microphone on the closing press when set to toggle")
    func stopSoundIsLeftToTheMicrophoneOnTheClosingPress() async {
        let harness = makeHarness(activation: .pressToToggle)
        await harness.controller.handle(.pressed)

        await harness.controller.handle(.pressed)

        #expect(harness.cue.plays == [.start])
        #expect(await harness.capture.calls.events == [.start, .stop])
    }
}

/// Rebinding, which is what changing the shortcut in Settings does.
@Suite("Changing the shortcut while it is running")
struct DictationControllerRebindTests {
    /// Covers rebinding only; the forwarding-task cancellation cannot be driven deterministically here.
    @Test("rebinds the monitor rather than ignoring the new shortcut")
    func rebindReachesTheMonitor() async throws {
        let harness = makeHarness()
        let second = HotkeyBinding(keyCode: 2, modifiers: [.control, .option])

        try await harness.controller.start(binding: .optionSpace)
        try await harness.controller.start(binding: second)

        #expect(harness.monitor.bindings == [.optionSpace, second])
    }
}

/// Changing the activation mode in Settings while a dictation is recording.
@Suite("Changing the activation mode while recording")
struct DictationControllerModeChangeTests {
    @Test("switching from hold to toggle mid-hold finishes the recording and keeps the words")
    func holdToToggleFinishesTheHold() async {
        let harness = makeHarness(activation: .holdToTalk)
        await harness.controller.handle(.pressed)
        harness.clock.advance(by: .seconds(3))

        await harness.controller.setActivation(.pressToToggle)

        #expect(await !harness.pipeline.currentState.isListening, "the microphone is closed")
        #expect(harness.inserter.received == [controllerTidied], "finished, not cancelled")
        #expect(await harness.capture.calls.events == [.start, .stop])

        await harness.controller.handle(.released)
        #expect(await harness.capture.calls.events == [.start, .stop], "the late release opens nothing")
    }

    @Test("switching from toggle to hold while toggled on finishes the recording")
    func toggleToHoldFinishesTheToggle() async {
        let harness = makeHarness(activation: .pressToToggle)
        await harness.controller.handle(.pressed)
        await harness.controller.handle(.released)
        harness.clock.advance(by: .seconds(3))

        await harness.controller.setActivation(.holdToTalk)

        #expect(await !harness.pipeline.currentState.isListening, "the microphone is closed")
        #expect(harness.inserter.received == [controllerTidied])
        #expect(await harness.capture.calls.events == [.start, .stop])
    }

    @Test("switching from toggle to hold with the key still down finishes once, and the release adds nothing")
    func toggleToHoldWithTheKeyDown() async {
        let harness = makeHarness(activation: .pressToToggle)
        await harness.controller.handle(.pressed)
        harness.clock.advance(by: .seconds(3))

        await harness.controller.setActivation(.holdToTalk)
        await harness.controller.handle(.released)

        #expect(await !harness.pipeline.currentState.isListening)
        #expect(harness.inserter.received == [controllerTidied])
        #expect(await harness.capture.calls.events == [.start, .stop])
    }

    @Test("switching to toggle ends hands-free, and the next press starts a fresh dictation")
    func holdToToggleEndsHandsFree() async {
        let harness = makeHarness(activation: .holdToTalk)
        await tap(harness)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)
        #expect(await harness.pipeline.currentState.isListening)

        await harness.controller.setActivation(.pressToToggle)
        #expect(await !harness.pipeline.currentState.isListening)
        #expect(harness.inserter.received == [controllerTidied])

        await harness.controller.handle(.pressed)
        #expect(await harness.pipeline.currentState.isListening, "the press opens a new dictation")
    }

    @Test("switching back to hold after hands-free ended lets a hold open the microphone")
    func handsFreeDoesNotOutliveTheModeChange() async {
        let harness = makeHarness(activation: .holdToTalk)
        await tap(harness)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)

        await harness.controller.setActivation(.pressToToggle)
        await harness.controller.setActivation(.holdToTalk)
        await harness.controller.handle(.pressed)

        #expect(await harness.pipeline.currentState.isListening, "no stale hands-free swallows the press")
        #expect(await Array(harness.capture.calls.events.suffix(3)) == [.start, .stop, .start])
    }

    @Test("setting the mode it already has leaves the recording alone")
    func sameModeChangesNothing() async {
        let harness = makeHarness(activation: .holdToTalk)
        await harness.controller.handle(.pressed)

        await harness.controller.setActivation(.holdToTalk)

        #expect(await harness.pipeline.currentState == .recording)
        #expect(await harness.capture.calls.events == [.start])
    }

    @Test("a mode change waits behind a queued press, then finishes what that press opened")
    func modeChangeQueuesBehindAPress() async {
        let harness = makeHarness(activation: .holdToTalk)

        harness.controller.submit(.pressed)
        await harness.controller.setActivation(.pressToToggle)

        #expect(await harness.capture.calls.events == [.start, .stop])
        #expect(await !harness.pipeline.currentState.isListening)
    }

    @Test("a modifier press still settling is forgotten, so its release under toggle opens nothing")
    func unsettledPressIsForgotten() async throws {
        let harness = makeHarness(activation: .holdToTalk)
        try await harness.controller.start(
            binding: HotkeyBinding(keyCode: 58, modifiers: [.option, .command, .control]))
        await harness.controller.handle(.pressed)

        await harness.controller.setActivation(.pressToToggle)
        await harness.controller.handle(.released)

        #expect(
            await harness.capture.calls.events == [.start, .cancel],
            "the key-down microphone closes with the mode change and nothing reopens it")
        await harness.controller.stop()
    }
}

/// The dock instruction must change when the gesture that ends the recording changes.
@Suite("The stop-gesture the dock should announce")
struct DictationControllerStopGestureTests {
    /// The default nothing-held state says the shortcut does nothing, so releasing is the stop.
    @Test("says the shortcut stops the recording only while a hold is open")
    func idleIsLetGo() async {
        let harness = makeHarness(activation: .holdToTalk)

        #expect(await harness.controller.currentStopGesture == .letGo)
    }

    @Test("a control-started recording tells the dock that a click can finish it")
    func controlStartReportsClickAgain() async {
        let spy = StopGestureSpy()
        let harness = makeHarness(activation: .holdToTalk, gestureSpy: spy)

        await harness.controller.toggleFromControl()

        #expect(await harness.controller.currentStopGesture == .clickAgain)
        #expect(spy.recorded == [.letGo, .clickAgain])
        await harness.controller.handle(.escapePressed)
        #expect(await harness.controller.currentStopGesture == .letGo)
        #expect(spy.recorded == [.letGo, .clickAgain, .letGo])
    }

    /// A press-to-toggle shortcut stays waiting for the next press even while the microphone is live.
    @Test("press-to-toggle says the shortcut must be pressed again to stop, not let go")
    func toggleIsPressAgain() async {
        let harness = makeHarness(activation: .pressToToggle)

        #expect(await harness.controller.currentStopGesture == .pressAgain)
    }

    /// A hold-to-talk double tap leaves the microphone open, so releasing no longer stops the recording.
    @Test("hands-free says the shortcut must be pressed again, even though the mode is hold")
    func handsFreeIsPressAgain() async {
        let spy = StopGestureSpy()
        let harness = makeHarness(gestureSpy: spy)

        await tap(harness)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)
        #expect(await harness.controller.currentStopGesture == .pressAgainHandsFree)

        // The dock was told once when hands-free flipped on, not when nothing happened.
        #expect(spy.recorded.last == .pressAgainHandsFree)
    }

    /// The dock has to be told, in order, as the recording hands a hold over to hands-free and back.
    @Test("reports let-go, hands-free and let-go in order across a double-tap cycle")
    func gestureMovesAcrossADoubleTapCycle() async {
        let spy = StopGestureSpy()
        let harness = makeHarness(gestureSpy: spy)

        // The dock is told the resting gesture once the controller reaches its actor, before any key.
        #expect(spy.recorded == [.letGo])

        // First double tap opens hands-free: let-go while the hold is open, then hands-free.
        await tap(harness)
        #expect(await harness.controller.currentStopGesture == .letGo)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)
        #expect(await harness.controller.currentStopGesture == .pressAgainHandsFree)

        // Second double tap closes it: hands-free, then let-go once the recording is over.
        harness.clock.advance(by: .seconds(2))
        await tap(harness)
        #expect(await harness.controller.currentStopGesture == .pressAgainHandsFree)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)
        #expect(await harness.controller.currentStopGesture == .letGo)

        // Initial let-go, the hands-free opening, and the return to let-go — and nothing else.
        #expect(spy.recorded == [.letGo, .pressAgainHandsFree, .letGo])
    }

    /// Press-to-toggle stays press-again from the first press of the shortcut through to the closing one.
    @Test("press-to-toggle never advertises a let-go, even mid-dictation")
    func toggleStaysPressAgain() async {
        let spy = StopGestureSpy()
        let harness = makeHarness(activation: .pressToToggle, gestureSpy: spy)

        // The dock is told the initial gesture once, and never told again — hands-free never changes.
        #expect(spy.recorded == [.pressAgain])

        await harness.controller.handle(.pressed)
        #expect(await harness.controller.currentStopGesture == .pressAgain)
        await harness.controller.handle(.released)
        #expect(await harness.controller.currentStopGesture == .pressAgain)

        await harness.controller.handle(.pressed)
        #expect(await harness.controller.currentStopGesture == .pressAgain)

        // Nothing further — no spurious updates from the two press/release pairs.
        #expect(spy.recorded == [.pressAgain])
    }

    /// A click on a control while hands-free finishes the dictation, and the dock goes back to holding.
    @Test("a control stop drops hands-free, so the next gesture is a hold-to-talk let-go")
    func controlStopClearsHandsFree() async {
        let spy = StopGestureSpy()
        let harness = makeHarness(gestureSpy: spy)

        await goHandsFree(harness)
        #expect(await harness.controller.currentStopGesture == .pressAgainHandsFree)

        await harness.controller.toggleFromControl()
        #expect(await harness.controller.currentStopGesture == .letGo)

        // Initial let-go, then the hands-free opening, then the return to let-go.
        #expect(spy.recorded == [.letGo, .pressAgainHandsFree, .letGo])
    }

    /// Helper reused by hands-free tests so the gesture spy sees the right setup path.
    private func goHandsFree(_ harness: ControllerHarness) async {
        await tap(harness)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)
    }
}

/// Starting a dictation from something clicked rather than something held.
@Suite("Dictating from a control")
struct DictationControllerControlTests {
    /// A click has no release, so it toggles. See Docs/pipeline-gestures.md.
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

    @Test("Start twice records once, and the second says it was already listening")
    func startTwiceRecordsOnce() async {
        let harness = makeHarness(activation: .holdToTalk)

        #expect(await harness.controller.command(.start) == .started)
        #expect(await harness.controller.command(.start) == .alreadyRecording)

        #expect(await harness.pipeline.currentState == .recording)
        #expect(await harness.capture.calls.events == [.start])
    }

    @Test("Stop with nothing recording changes nothing and says so")
    func stopWithNothingRecording() async {
        let harness = makeHarness(activation: .holdToTalk)

        #expect(await harness.controller.command(.stop) == .nothingRecording)
        #expect(await harness.controller.command(.cancel) == .nothingRecording)

        #expect(await harness.capture.calls.events.isEmpty)
        #expect(harness.inserter.received.isEmpty)
    }

    @Test("Stop finishes and inserts the words")
    func stopFinishesAndInserts() async {
        let harness = makeHarness(activation: .holdToTalk)
        _ = await harness.controller.command(.start)

        #expect(await harness.controller.command(.stop) == .finished)
        #expect(harness.inserter.received == [controllerTidied])
        #expect(await harness.capture.calls.events == [.start, .stop])
    }

    @Test("Cancel mid-recording inserts nothing, as Escape does")
    func cancelInsertsNothing() async {
        let harness = makeHarness(activation: .holdToTalk)
        _ = await harness.controller.command(.start)

        #expect(await harness.controller.command(.cancel) == .cancelled)
        #expect(harness.inserter.received.isEmpty)
        #expect(!(await harness.pipeline.currentState.isListening))
        #expect(await harness.controller.currentStopGesture == .letGo)
    }

    @Test("a shortcut hold still finishes a recording started by a click")
    func shortcutFinishesClickStartedRecording() async {
        let harness = makeHarness(activation: .holdToTalk)
        await harness.controller.toggleFromControl()

        await harness.controller.handle(.pressed)
        harness.clock.advance(by: .seconds(1))
        await harness.controller.handle(.released)

        #expect(!(await harness.pipeline.currentState.isListening))
        #expect(harness.inserter.received == [controllerTidied])
        #expect(await harness.controller.currentStopGesture == .letGo)
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

    @Test("the start cue sounds for a control, as it does for the shortcut")
    func controlPlaysTheCue() async {
        let harness = makeHarness(activation: .holdToTalk)
        await harness.controller.toggleFromControl()
        #expect(harness.cue.plays == [.start])
        await harness.controller.toggleFromControl()
        #expect(harness.cue.plays == [.start], "the stop cue is the microphone's")
    }

    @Test("a click waits its turn behind a key press already queued, rather than jumping it")
    func controlQueuesBehindAKeyPress() async {
        let harness = makeHarness(activation: .holdToTalk)

        harness.controller.submit(.pressed)
        await harness.controller.toggleFromControl()

        // The press opens the microphone first, so the click is what finishes it.
        #expect(await harness.capture.calls.events == [.start, .stop])
        #expect(harness.inserter.received == [controllerTidied])
    }

    /// Leaves a double-tap dictation listening, as the shortcut does.
    private func goHandsFree(_ harness: ControllerHarness) async {
        await tap(harness)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)
    }

    @Test("a click that stops a double-tap dictation leaves the hold working")
    func clickStopsHandsFreeThenAHoldWorks() async {
        let harness = makeHarness()
        await goHandsFree(harness)
        await harness.controller.toggleFromControl()
        #expect(harness.inserter.received == [controllerTidied], "the click finished it")

        harness.clock.advance(by: .seconds(2))
        await harness.controller.handle(.pressed)
        #expect(await harness.pipeline.currentState.isListening, "the hold opens the microphone")
        harness.clock.advance(by: .seconds(3))
        await harness.controller.handle(.released)
        #expect(harness.inserter.received == [controllerTidied, controllerTidied])
    }

    @Test("a click that stops a double-tap dictation leaves the double tap working")
    func clickStopsHandsFreeThenADoubleTapWorks() async {
        let harness = makeHarness()
        await goHandsFree(harness)
        await harness.controller.toggleFromControl()

        harness.clock.advance(by: .seconds(2))
        await goHandsFree(harness)
        #expect(await harness.pipeline.currentState.isListening, "the double tap opens it again")

        harness.clock.advance(by: .seconds(2))
        await goHandsFree(harness)
        #expect(await harness.pipeline.currentState.isListening == false, "and another closes it")
        #expect(harness.inserter.received == [controllerTidied, controllerTidied])
    }

    @Test("a double-tap dictation ended by the pipeline itself leaves the hold working")
    func handsFreeEndedElsewhereThenAHoldWorks() async {
        let harness = makeHarness()
        await goHandsFree(harness)
        await harness.pipeline.cancel()

        harness.clock.advance(by: .seconds(2))
        await harness.controller.handle(.pressed)
        #expect(await harness.pipeline.currentState.isListening)
    }

    @Test("a double-tap dictation ended elsewhere leaves a modifier-only double tap working")
    func handsFreeEndedElsewhereThenAModifierDoubleTapWorks() async throws {
        let harness = makeHarness()
        try await harness.controller.start(
            binding: HotkeyBinding(keyCode: 58, modifiers: [.option, .command, .control]))
        await goHandsFree(harness)
        #expect(await harness.pipeline.currentState.isListening, "two taps inside the settle go hands-free")
        await harness.pipeline.cancel()

        harness.clock.advance(by: .seconds(2))
        await goHandsFree(harness)
        #expect(await harness.pipeline.currentState.isListening, "the next double tap opens it again")
        await harness.controller.stop()
    }

    /// A press that arrives during a click-started dictation did not open the microphone, so it cannot replay the start cue, restart the cap, or set the flag whose truth would let a slip or cancellation cancel the recording.
    @Test("a press during a click-started dictation leaves the recording alone")
    func pressDuringControlStartedIsANoOp() async {
        let harness = makeHarness(activation: .holdToTalk)

        await harness.controller.toggleFromControl()
        #expect(await harness.pipeline.currentState == .recording)
        #expect(harness.cue.plays == [.start])

        await harness.controller.handle(.pressed)

        #expect(harness.cue.plays == [.start], "the press does not replay the start cue")
        #expect(
            await harness.pipeline.currentState == .recording,
            "the click-started dictation survives")

        await harness.controller.handle(.released)
    }

    /// A slip release used to call `pipeline.cancel()` on the click-started dictation and discard every word.
    @Test("a slip during a click-started dictation keeps the words and finishes the recording")
    func slipDuringControlStartedFinishesTheRecording() async {
        let harness = makeHarness(activation: .holdToTalk)

        await harness.controller.toggleFromControl()
        #expect(await harness.pipeline.currentState == .recording)

        await harness.controller.handle(.pressed)
        harness.clock.advance(by: justUnderTheMinimum)
        await harness.controller.handle(.released)

        #expect(harness.inserter.received == [controllerTidied], "finished, not cancelled")
        #expect(
            await harness.pipeline.currentState == .inserted(controllerOutcome),
            "the words landed in the user's app")
        #expect(await harness.capture.calls.events == [.start, .stop])
    }

    /// A `.cancelled` event used to discard the click-started dictation because the press had falsely claimed to have opened it.
    @Test("a cancelled press during a click-started dictation leaves the recording alone")
    func cancelledPressDuringControlStartedLeavesTheRecording() async {
        let harness = makeHarness(activation: .holdToTalk)

        await harness.controller.toggleFromControl()
        #expect(await harness.pipeline.currentState == .recording)

        await harness.controller.handle(.pressed)
        await harness.controller.handle(.cancelled)

        #expect(
            await harness.pipeline.currentState == .recording,
            "the click-started dictation survives a withdrawn press")

        await harness.controller.toggleFromControl()
        #expect(harness.inserter.received == [controllerTidied])
    }
}

@Suite("Escape cancellation")
struct DictationControllerEscapeTests {
    @Test("Escape discards a press-to-toggle recording")
    func escapeCancelsToggle() async {
        let harness = makeHarness(activation: .pressToToggle)
        await harness.controller.handle(.pressed)
        await harness.controller.handle(.released)
        #expect(await harness.pipeline.currentState == .recording)

        await harness.controller.handle(.escapePressed)

        #expect(await harness.pipeline.currentState == .idle)
        #expect(harness.inserter.received.isEmpty)
        #expect(await harness.capture.calls.events == [.start, .cancel], "discarded, not stopped")
    }

    @Test("Escape discards a hands-free recording")
    func escapeCancelsHandsFree() async {
        let harness = makeHarness()
        await tap(harness)
        harness.clock.advance(by: .milliseconds(120))
        await tap(harness)
        #expect(await harness.pipeline.currentState == .recording)
        #expect(await harness.controller.currentStopGesture == .pressAgainHandsFree)

        await harness.controller.handle(.escapePressed)

        #expect(await harness.pipeline.currentState == .idle)
        #expect(await harness.controller.currentStopGesture == .letGo)
        #expect(harness.inserter.received.isEmpty)
        // The first tap is a slip the controller cancels; the second opens the microphone hands-free.
        #expect(
            await harness.capture.calls.events == [.start, .cancel, .start, .cancel],
            "discarded, not stopped")
    }
}

// MARK: - Being let go of

@Suite("A controller nothing holds", .timeLimit(.minutes(1)))
struct DictationControllerLifetimeTests {
    /// The tap and its thread go with the controller, so a controller that cannot die leaks both.
    @Test("is deallocated, rather than kept alive by the task reading its own gestures")
    func isDeallocated() async throws {
        weak var released: DictationController<ManualClock>?
        do {
            let controller = makeHarness().controller
            released = controller
            #expect(released != nil)
            await controller.stop()
        }
        // The task holds the stream, not the controller, so the drop is what has to be waited for.
        try await eventually { released == nil }
        #expect(released == nil, "the controller outlived every reference to it")
    }
}
