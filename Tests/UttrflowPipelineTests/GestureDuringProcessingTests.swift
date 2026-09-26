// Tests that a press made while the last dictation is processed is decided when it arrives.
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

private final class PlainCleaner: TranscriptCleaning {
    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        TransformationResult(text: "Hello there.", producedBy: .foundationModels)
    }
}

/// An inserter that holds every insertion until the test lets it through.
private final class HeldInserter: TextInserting {
    private struct State {
        var received: [String] = []
        var waiting: [CheckedContinuation<Void, Never>] = []
        var isOpen = false
    }

    private let state = Mutex(State())

    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        await withCheckedContinuation { go in
            let proceed = state.withLock { state -> Bool in
                state.received.append(text)
                guard !state.isOpen else { return true }
                state.waiting.append(go)
                return false
            }
            if proceed { go.resume() }
        }
        return InsertionAttempt(.accessibility)
    }

    /// Lets every held and later insertion through.
    func open() {
        let waiting = state.withLock { state in
            state.isOpen = true
            defer { state.waiting = [] }
            return state.waiting
        }
        waiting.forEach { $0.resume() }
    }

    var received: [String] { state.withLock { $0.received } }
}

private struct Rig {
    let controller: DictationController<ManualClock>
    let pipeline: DictationPipeline
    let capture: FakeAudioCaptureEngine
    let inserter: HeldInserter
    let clock: ManualClock
}

private func makeRig() -> Rig {
    let capture = FakeAudioCaptureEngine()
    let inserter = HeldInserter()
    let pipeline = DictationPipeline(
        capture: capture,
        speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: "hello there"))),
        cleaner: PlainCleaner(),
        context: FakeContextEngine(context: .fixture()),
        inserter: inserter,
        clock: ManualClock()
    )
    let clock = ManualClock()
    let controller = DictationController(pipeline: pipeline, monitor: QuietMonitor(), clock: clock)
    return Rig(
        controller: controller, pipeline: pipeline, capture: capture, inserter: inserter, clock: clock)
}

/// Holds and releases the shortcut, then waits until the words are being inserted and held there.
private func dictateUntilInsertion(_ rig: Rig) async {
    rig.controller.submit(.pressed)
    await rig.controller.caughtUp()
    rig.clock.advance(by: .seconds(2))
    rig.controller.submit(.released)
    await rig.controller.caughtUp()
    while rig.inserter.received.isEmpty { await Task.yield() }
}

@Suite("A press made while the last dictation is processed", .timeLimit(.minutes(1)))
struct GestureDuringProcessingTests {

    @Test("is refused when it arrives, and a quick release after it cancels nothing")
    func pressAndReleaseDuringProcessing() async {
        let rig = makeRig()
        await dictateUntilInsertion(rig)

        rig.controller.submit(.pressed)
        rig.clock.advance(by: .milliseconds(50))
        rig.controller.submit(.released)
        await rig.controller.caughtUp()

        #expect(await rig.capture.calls.events == [.start, .stop])
        rig.inserter.open()
        await rig.controller.drained()
        #expect(rig.inserter.received == ["Hello there."])
        guard case .inserted = await rig.pipeline.currentState else {
            Issue.record("the first dictation did not finish")
            return
        }
    }

    @Test("still held once the words land, opens no microphone late")
    func pressHeldPastProcessing() async {
        let rig = makeRig()
        await dictateUntilInsertion(rig)

        rig.controller.submit(.pressed)
        await rig.controller.caughtUp()
        rig.inserter.open()
        await rig.controller.drained()
        rig.clock.advance(by: .seconds(1))
        rig.controller.submit(.released)
        await rig.controller.drained()

        #expect(await rig.capture.calls.events == [.start, .stop])
        #expect(rig.inserter.received == ["Hello there."])
    }

    @Test("after the words land, the next hold dictates as usual")
    func nextHoldAfterProcessing() async {
        let rig = makeRig()
        await dictateUntilInsertion(rig)
        rig.inserter.open()
        await rig.controller.drained()

        rig.controller.submit(.pressed)
        await rig.controller.caughtUp()
        rig.clock.advance(by: .seconds(2))
        rig.controller.submit(.released)
        await rig.controller.drained()

        #expect(rig.inserter.received == ["Hello there.", "Hello there."])
    }
}
