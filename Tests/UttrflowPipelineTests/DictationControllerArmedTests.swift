// Tests the listening look the controller announces from key-down, before the microphone has opened.
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// Records every armed signal the controller sends, in order.
private final class ArmedSpy: Sendable {
    private let log = Mutex<[Bool]>([])

    func record(_ armed: Bool) { log.withLock { $0.append(armed) } }

    var signals: [Bool] { log.withLock { $0 } }
}

/// Waits until the capture engine has been asked to start, which is while the microphone is still opening.
private func untilStartRequested(_ capture: FakeAudioCaptureEngine) async {
    for _ in 0..<10_000 where await capture.calls.events.isEmpty { await Task.yield() }
}

private let modifierBinding = HotkeyBinding(keyCode: 58, modifiers: [.option, .command, .control])

@Suite("The listening look at key-down")
struct DictationControllerArmedTests {
    @Test("a modifier key-down arms the look as the microphone opens")
    func keyDownArms() async throws {
        let spy = ArmedSpy()
        let harness = makeHarness(onArmed: { spy.record($0) })
        await harness.capture.holdStart()
        try await harness.controller.start(binding: modifierBinding)

        let press = Task { await harness.controller.handle(.pressed) }
        await untilStartRequested(harness.capture)

        #expect(spy.signals == [true])
        await harness.capture.releaseStart()
        await press.value
        #expect(spy.signals == [true])
        #expect(await harness.capture.calls.events == [.start])
        await harness.controller.stop()
    }

    @Test("a release before the hold settles takes the look off once")
    func earlyReleaseDisarms() async throws {
        let spy = ArmedSpy()
        let harness = makeHarness(onArmed: { spy.record($0) })
        try await harness.controller.start(binding: modifierBinding)
        await harness.controller.handle(.pressed)

        await harness.controller.handle(.released)

        #expect(spy.signals == [true, false])
        await harness.controller.stop()
    }

    @Test("escape during the press takes the look off")
    func escapeDisarms() async throws {
        let spy = ArmedSpy()
        let harness = makeHarness(onArmed: { spy.record($0) })
        try await harness.controller.start(binding: modifierBinding)
        await harness.controller.handle(.pressed)

        await harness.controller.handle(.escapePressed)

        #expect(spy.signals == [true, false])
        await harness.controller.stop()
    }

    @Test("a control click arms the look and a recording that starts leaves it to the state")
    func controlStartArmsOnly() async {
        let spy = ArmedSpy()
        let harness = makeHarness(onArmed: { spy.record($0) })
        await harness.capture.holdStart()

        let toggle = Task { await harness.controller.toggleFromControl() }
        await untilStartRequested(harness.capture)

        #expect(spy.signals == [true])
        await harness.capture.releaseStart()
        await toggle.value
        #expect(spy.signals == [true])
        #expect(harness.cue.plays == [.start])
        await harness.controller.handle(.escapePressed)
    }

    @Test("a failed open leaves the failure to the state and sends no disarm")
    func failedOpenSendsNoDisarm() async {
        let spy = ArmedSpy()
        let harness = makeHarness(
            captureStart: .failure(.noInputDevice), onArmed: { spy.record($0) })

        await harness.controller.toggleFromControl()

        #expect(spy.signals == [true])
        #expect(harness.cue.plays.isEmpty)
        let state = await harness.pipeline.currentState
        guard case .failed = state else {
            Issue.record("the failed open should be the pipeline's state")
            return
        }
    }
}
