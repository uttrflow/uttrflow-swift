// Tests that a release the tap never delivers is still noticed by the real-state poll. #609
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// A keyboard that hands strokes to the monitor on the calling thread and never reports a release on its own.
private final class SilentSource: KeyboardEventSource {
    private struct Sink: Sendable {
        let call: @Sendable (KeyStroke) -> Void
    }

    private let sink = Mutex<Sink?>(nil)

    func start(
        _ deliver: @escaping @Sendable (KeyStroke) -> Void,
        consumeKeyDown: Bool = false
    ) throws(KeyboardSourceError) {
        sink.withLock { $0 = Sink(call: deliver) }
    }

    func stop() { sink.withLock { $0 = nil } }

    func send(_ stroke: KeyStroke) { sink.withLock { $0 }?.call(stroke) }
}

/// A key-state reader a test can flip, standing in for `CGEventSource`.
private final class FakeKeyState: RealKeyStateReading, Sendable {
    private let held = Mutex<Bool>(true)

    func isDown(_ binding: HotkeyBinding) -> Bool { held.withLock { $0 } }
    func release() { held.withLock { $0 = false } }
}

private let optionSpaceDown = KeyStroke(keyCode: 49, modifiers: [.option], phase: .down)

@Suite("Activation monitor: reconciling against the real key state")
struct ActivationMonitorReconciliationTests {
    @Test("a release the tap never delivers is found by the poll within the interval")
    @MainActor
    func releaseNeverDeliveredIsReconciled() async throws {
        let source = SilentSource()
        let keyState = FakeKeyState()
        let monitor = ActivationMonitor(source: source, keyState: keyState, strokeLeftLock: {})
        try monitor.start(binding: .optionSpace)

        var events = monitor.events.makeAsyncIterator()
        source.send(optionSpaceDown)
        let pressed = await events.next()
        #expect(pressed == .pressed)

        // The tap never delivers a key-up or flags-changed event: only the poll can end this hold.
        keyState.release()
        let released = await events.next()
        #expect(released == .released)

        monitor.stop()
    }

    @Test("the poll leaves a hold alone while the real key state still reports it down")
    @MainActor
    func heldKeyIsNotReconciledAway() async throws {
        let source = SilentSource()
        let keyState = FakeKeyState()
        let monitor = ActivationMonitor(source: source, keyState: keyState, strokeLeftLock: {})
        try monitor.start(binding: .optionSpace)

        var events = monitor.events.makeAsyncIterator()
        source.send(optionSpaceDown)
        let pressed = await events.next()
        #expect(pressed == .pressed)

        // Give the poll a few intervals to run; the key state never says it let go.
        try await Task.sleep(for: .milliseconds(600))

        // The only release left is the one `stop()` owes, not one the poll invented.
        monitor.stop()
        let released = await events.next()
        #expect(released == .released)
    }
}
