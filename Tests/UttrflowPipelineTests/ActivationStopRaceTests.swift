// Tests that a stop racing a keystroke does not leave the microphone open.
import Dispatch
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A keyboard that hands strokes to the monitor on whichever thread calls `send`.
private final class HandFedSource: KeyboardEventSource {
    private struct Sink: Sendable {
        let call: @Sendable (KeyEvent) -> Void
    }

    private let sink = Mutex<Sink?>(nil)

    func start(
        _ deliver: @escaping @Sendable (KeyEvent) -> Void,
        consumeKeyDown: Bool = false
    ) throws(KeyboardSourceError) {
        sink.withLock { $0 = Sink(call: deliver) }
    }

    func stop() { sink.withLock { $0 = nil } }

    func send(_ stroke: KeyEvent) { sink.withLock { $0 }?.call(stroke) }
}

/// A monitor that never reports anything, so the test hands the controller each event itself.
private final class SilentRaceMonitor: HotkeyMonitoring {
    private let pair = AsyncStream<HotkeyEvent>.makeStream()
    @MainActor func start(binding: HotkeyBinding) throws(HotkeyError) {}
    func stop() {}
    var events: AsyncStream<HotkeyEvent> { pair.stream }
}

private final class RaceCleaner: TranscriptCleaning {
    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        TransformationResult(text: "Hello.", producedBy: .foundationModels)
    }
}

private final class RaceInserter: TextInserting {
    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        InsertionAttempt(.accessibility)
    }
}

/// Stops the monitor while ⌥Space down, sent on a thread of its own, is held past the lock.
@MainActor
private func stopDuringAPress() throws -> ActivationMonitor {
    let source = HandFedSource()
    let arrived = DispatchSemaphore(value: 0)
    let proceed = DispatchSemaphore(value: 0)
    let monitor = ActivationMonitor(
        source: source,
        strokeLeftLock: {
            arrived.signal()
            proceed.wait()
        })
    try monitor.start(binding: .optionSpace)
    let typed = DispatchSemaphore(value: 0)
    Thread {
        source.send(KeyEvent(keyCode: 49, modifiers: [.option], phase: .down))
        typed.signal()
    }.start()
    arrived.wait()
    monitor.stop()
    proceed.signal()
    typed.wait()
    return monitor
}

@Suite("Dictation after a stop that raced a keystroke")
struct ActivationStopRaceTests {
    @Test("a stop during a press leaves the microphone closed")
    @MainActor
    func stopDuringPressClosesTheMicrophone() async throws {
        let monitor = try stopDuringAPress()

        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(),
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: "hello"))),
            cleaner: RaceCleaner(),
            context: FakeContextEngine(context: .fixture()),
            inserter: RaceInserter(),
            clock: ManualClock()
        )
        let controller = DictationController(
            pipeline: pipeline, monitor: SilentRaceMonitor(), clock: ManualClock())
        try await controller.start(binding: .optionSpace)

        var events = monitor.events.makeAsyncIterator()
        for _ in 0..<2 {
            if let event = await events.next() { await controller.handle(event) }
        }
        await controller.drained()

        #expect(await !pipeline.currentState.isListening)
    }
}
