// Tests that Escape abandons a dictation still being transcribed, tidied or inserted.
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A monitor that never reports anything, so the test submits each event itself.
private final class QuietMonitor: HotkeyMonitoring {
    private let pair = AsyncStream<HotkeyEvent>.makeStream()
    @MainActor func start(binding: HotkeyBinding) throws(HotkeyError) {}
    func stop() {}
    var events: AsyncStream<HotkeyEvent> { pair.stream }
}

/// Holds every caller until the test opens it, and says whether one has arrived.
private final class Gate: Sendable {
    private struct State {
        var arrivals = 0
        var waiting: [CheckedContinuation<Void, Never>] = []
        var isOpen = false
    }

    private let state = Mutex(State())

    func pass() async {
        await withCheckedContinuation { go in
            let proceed = state.withLock { state -> Bool in
                state.arrivals += 1
                guard !state.isOpen else { return true }
                state.waiting.append(go)
                return false
            }
            if proceed { go.resume() }
        }
    }

    func open() {
        let waiting = state.withLock { state in
            state.isOpen = true
            defer { state.waiting = [] }
            return state.waiting
        }
        waiting.forEach { $0.resume() }
    }

    var hasArrival: Bool { state.withLock { $0.arrivals > 0 } }
}

/// A recogniser that waits at the gate before it answers.
private struct GatedSpeech: SpeechEngine {
    let gate: Gate
    var kind: SpeechEngineKind { .whisperKit }
    func prepare() async throws(SpeechEngineError) {}
    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        await gate.pass()
        return .fixture(text: "hello there")
    }
}

/// An inserter that waits at the gate after taking the words.
private final class GatedInserter: TextInserting {
    let gate: Gate
    private let taken = Mutex<[String]>([])

    init(gate: Gate) {
        self.gate = gate
    }

    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        taken.withLock { $0.append(text) }
        await gate.pass()
        return InsertionAttempt(.accessibility)
    }

    var received: [String] { taken.withLock { $0 } }
}

enum HeldStage: CaseIterable, Sendable {
    case transcribing, tidying, inserting
}

private struct Rig {
    let controller: DictationController<ManualClock>
    let pipeline: DictationPipeline
    let inserter: GatedInserter
    let recordings: FakeRecordingKeeper
    let recording: KeptRecording
    let gate: Gate
    let clock: ManualClock
}

private func makeRig(holding stage: HeldStage) -> Rig {
    let gate = Gate()
    let open = Gate()
    open.open()
    let recording = KeptRecording(id: UUID(), when: Date(), duration: .seconds(2))
    let recordings = FakeRecordingKeeper(current: recording)
    let inserter = GatedInserter(gate: stage == .inserting ? gate : open)
    let cleanerGate = stage == .tidying ? gate : open
    let pipeline = DictationPipeline(
        capture: FakeAudioCaptureEngine(),
        speech: GatedSpeech(gate: stage == .transcribing ? gate : open),
        cleaner: FakeTranscriptCleaner(
            answering: ScriptedSequence(
                .success(TransformationResult(text: "Hello there.", producedBy: .rules))),
            holding: { await cleanerGate.pass() }),
        context: FakeContextEngine(context: .fixture()),
        inserter: inserter,
        recordings: recordings,
        clock: ManualClock()
    )
    let clock = ManualClock()
    let controller = DictationController(pipeline: pipeline, monitor: QuietMonitor(), clock: clock)
    return Rig(
        controller: controller, pipeline: pipeline, inserter: inserter, recordings: recordings,
        recording: recording, gate: gate, clock: clock)
}

@Suite("Escape while a dictation is processed", .timeLimit(.minutes(1)))
struct CancelDuringProcessingTests {

    @Test(
        "ends at rest, writes nothing more and keeps the recording",
        arguments: HeldStage.allCases)
    func escapeDuringProcessing(_ stage: HeldStage) async throws {
        let rig = makeRig(holding: stage)
        rig.controller.submit(.pressed)
        await rig.controller.caughtUp()
        rig.clock.advance(by: .seconds(2))
        rig.controller.submit(.released)
        await rig.controller.caughtUp()
        try await eventually { rig.gate.hasArrival }
        let held: DictationState =
            switch stage {
            case .transcribing: .transcribing
            case .tidying: .tidying
            case .inserting: .inserting(into: nil)
            }
        #expect((await rig.pipeline.currentState).isStage(of: held))

        rig.controller.submit(.escapePressed)
        await rig.controller.caughtUp()
        #expect(await rig.pipeline.currentState == .idle)

        rig.gate.open()
        await rig.controller.drained()

        // Still at rest once the abandoned stage returns, so nothing was posted after the cancel.
        #expect(await rig.pipeline.currentState == .idle)
        if stage != .inserting { #expect(rig.inserter.received.isEmpty) }
        #expect(await rig.recordings.discarded.isEmpty)
    }

    @Test("a spoken Cancel reaches a dictation being processed, as Escape does")
    func cancelCommandDuringProcessing() async throws {
        let rig = makeRig(holding: .transcribing)
        rig.controller.submit(.pressed)
        await rig.controller.caughtUp()
        rig.clock.advance(by: .seconds(2))
        rig.controller.submit(.released)
        await rig.controller.caughtUp()
        try await eventually { rig.gate.hasArrival }

        // Answered only once the abandoned stage returns, so the gate is opened while it waits.
        async let outcome = rig.controller.command(.cancel)
        try await eventually { await rig.pipeline.currentState == .idle }
        rig.gate.open()
        #expect(await outcome == .cancelled)
        await rig.controller.drained()

        #expect(await rig.pipeline.currentState == .idle)
        #expect(rig.inserter.received.isEmpty)
        #expect(await rig.recordings.discarded.isEmpty)
    }

    @Test("Escape at rest changes nothing")
    func escapeAtRest() async {
        let rig = makeRig(holding: .transcribing)
        rig.controller.submit(.escapePressed)
        await rig.controller.drained()

        #expect(await rig.pipeline.currentState == .idle)
        #expect(await rig.controller.command(.cancel) == .nothingRecording)
    }
}
