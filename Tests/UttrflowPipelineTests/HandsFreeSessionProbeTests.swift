// Probes a hands-free session end to end: the key actions it costs and what VoiceOver hears.
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A ``HotkeyMonitoring`` that watches nothing; the probe hands gestures to the controller itself.
private struct SilentMonitor: HotkeyMonitoring {
    let events = AsyncStream<HotkeyEvent> { $0.finish() }

    @MainActor func start(binding: HotkeyBinding) throws(HotkeyError) {}

    func stop() {}
}

/// Every state the pipeline passes through, kept as it is published.
private final class StateLog: Sendable {
    private let seen = Mutex<[DictationState]>([])

    func record(_ state: DictationState) {
        seen.withLock { $0.append(state) }
    }

    var states: [DictationState] { seen.withLock { $0 } }
}

/// One step of the session, with the key presses it took and what VoiceOver was told.
struct ProbeStep: Equatable {
    let name: String
    let keyPresses: Int
    let announcements: [String]
}

/// Runs start, dictate, correct and stop through the real controller and pipeline, as the app wires them.
private actor HandsFreeProbe {
    private let clock = ManualClock()
    private let inserter = FakeTextInserter()
    private let log = StateLog()
    private let pipeline: DictationPipeline
    private let controller: DictationController<ManualClock>
    private var presses = 0
    private var announced = 0
    private var announcer = DictationAnnouncer<ManualClock.Instant>(
        repeatWindow: DictationController<ManualClock>.doubleTapWindow)

    init(heard: String) {
        pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(),
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: heard))),
            cleaner: FakeTranscriptCleaner(),
            context: FakeContextEngine(context: .fixture()),
            inserter: inserter,
            clock: ManualClock())
        controller = DictationController(
            pipeline: pipeline, monitor: SilentMonitor(), commandMonitor: SilentMonitor(),
            activation: .holdToTalk, clock: clock)
    }

    var inserted: [String] { inserter.received }

    func listen() async {
        let states = await pipeline.states()
        let log = log
        Task { for await state in states { log.record(state) } }
        await Task.yield()
    }

    /// The menu bar's Talk button or the Start Dictation intent, which Voice Control and Siri reach.
    func startFromControl() async {
        _ = await controller.command(.start)
    }

    /// The same control again (Stop), the gesture a control-started recording shows.
    func stopFromControl() async {
        _ = await controller.command(.stop)
    }

    /// One press and release of a key, short enough to count as a tap.
    private func tap(_ route: UtteranceRoute) async {
        presses += 1
        await controller.handle(.pressed, from: route)
        clock.advance(by: DictationController<ManualClock>.minimumHold - .milliseconds(1))
        await controller.handle(.released, from: route)
    }

    /// A double tap of the dictation key, the one hands-free gesture.
    func doubleTap() async {
        await tap(.dictation)
        clock.advance(by: .milliseconds(120))
        await tap(.dictation)
    }

    /// A hold of the command key while speaking, the only way to say an edit command.
    func holdCommandKey() async {
        presses += 1
        await controller.handle(.pressed, from: .command)
        clock.advance(by: DictationController<ManualClock>.minimumHold + .milliseconds(1))
        await controller.handle(.released, from: .command)
    }

    func waitForIdle() async throws {
        try await eventually { await self.pipeline.currentState.isListening == false }
        try await eventually { await self.pipeline.currentState.isBusy == false }
    }

    /// The step's cost since the last call, and what VoiceOver was told during it.
    func step(_ name: String) async -> ProbeStep {
        for _ in 0..<20 { await Task.yield() }
        let states = log.states
        let now = clock.now
        let said = states[announced...].compactMap { announcer.announcement(for: $0, at: now)?.text }
        announced = states.count
        defer { presses = 0 }
        return ProbeStep(name: name, keyPresses: presses, announcements: said)
    }
}

@Suite("Hands-free session probe: key actions and announcements, start to stop", .serialized)
struct HandsFreeSessionProbeTests {
    private static let heard = "send the report to the team on friday"

    /// The measured session; `Docs/segments.md` lists each key press with the issue that removes it.
    @Test("start, dictate, correct and stop: the key presses and what VoiceOver hears")
    func session() async throws {
        let probe = HandsFreeProbe(heard: Self.heard)
        await probe.listen()
        var steps: [ProbeStep] = []

        await probe.startFromControl()
        steps.append(await probe.step("start"))

        steps.append(await probe.step("dictate"))

        await probe.stopFromControl()
        try await probe.waitForIdle()
        steps.append(await probe.step("stop"))

        await probe.holdCommandKey()
        try await probe.waitForIdle()
        steps.append(await probe.step("correct"))

        for step in steps {
            print("hands-free probe: \(step.name) keyPresses=\(step.keyPresses) said=\(step.announcements)")
        }
        #expect(steps.map(\.keyPresses) == [0, 0, 0, 1])
        #expect(steps.map(\.keyPresses).reduce(0, +) == 1)
        #expect(steps[0].announcements == ["Listening."], "a control opens the microphone once")
        #expect(steps[2].announcements.contains { $0.hasPrefix("Inserted:") })
        #expect(
            steps[3].announcements.last
                == "That isn't an edit command Uttrflow knows, so nothing was changed.",
            "no edit command is registered, so a spoken correction changes nothing")
        #expect(await probe.inserted.count == 1, "the correction typed nothing, and changed nothing")
    }

    /// The keyboard route remains measured alongside the zero-key control route.
    @Test("double tap, dictate, correct and double tap: key presses and announcements")
    func keyboardSession() async throws {
        let probe = HandsFreeProbe(heard: Self.heard)
        await probe.listen()
        var steps: [ProbeStep] = []

        await probe.doubleTap()
        steps.append(await probe.step("start"))

        steps.append(await probe.step("dictate"))

        await probe.doubleTap()
        try await probe.waitForIdle()
        steps.append(await probe.step("stop"))

        await probe.holdCommandKey()
        try await probe.waitForIdle()
        steps.append(await probe.step("correct"))

        for step in steps {
            print(
                "hands-free keyboard probe: \(step.name) keyPresses=\(step.keyPresses) said=\(step.announcements)"
            )
        }
        #expect(steps.map(\.keyPresses) == [2, 0, 2, 1])
        #expect(steps.map(\.keyPresses).reduce(0, +) == 5)
        #expect(
            steps[0].announcements == ["Listening."],
            "a double tap that goes hands-free announces once")
        #expect(steps[2].announcements.contains { $0.hasPrefix("Inserted:") })
        #expect(
            steps[3].announcements.last
                == "That isn't an edit command Uttrflow knows, so nothing was changed.",
            "no edit command is registered, so a spoken correction changes nothing")
        #expect(await probe.inserted.count == 1, "the correction typed nothing, and changed nothing")
    }
}
