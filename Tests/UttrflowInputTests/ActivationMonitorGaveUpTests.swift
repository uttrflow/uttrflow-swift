// Tests that a source giving up its tap for good releases a held press and is rebuilt after resting. See issue #607.
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// A keyboard whose tap can be told to give up, and that counts how many times it was started.
private final class SourceThatGivesUp: KeyboardEventSource, @unchecked Sendable {
    private let sink = Mutex<(@Sendable (KeyStroke) -> Void)?>(nil)
    private let gaveUpHandler = Mutex<(@Sendable () -> Void)?>(nil)
    let startCount = Mutex<Int>(0)

    func start(
        _ deliver: @escaping @Sendable (KeyStroke) -> Void,
        consumeKeyDown: Bool = false
    ) throws(KeyboardSourceError) {
        sink.withLock { $0 = deliver }
        startCount.withLock { $0 += 1 }
    }

    func stop() { sink.withLock { $0 = nil } }

    func onGaveUp(_ handler: @escaping @Sendable () -> Void) { gaveUpHandler.withLock { $0 = handler } }

    func send(_ stroke: KeyStroke) { sink.withLock { $0 }?(stroke) }

    /// Fires the handler the monitor registered, as the real tap does when `shouldReEnable()` refuses.
    func giveUp() { gaveUpHandler.withLock { $0 }?() }
}

private let optionSpaceDown = KeyStroke(keyCode: 49, modifiers: [.option], phase: .down)

@Suite("Activation monitor: the source giving up")
struct ActivationMonitorGaveUpTests {
    @Test("a hold in progress when the source gives up is released, so the microphone does not stay open")
    @MainActor
    func releasesAHeldPress() async throws {
        let source = SourceThatGivesUp()
        // A rest long enough that the rebuild cannot race the assertions below.
        let monitor = ActivationMonitor(source: source, strokeLeftLock: {}, restSeconds: 3600)
        try monitor.start(binding: .optionSpace)
        source.send(optionSpaceDown)

        var events = monitor.events.makeAsyncIterator()
        #expect(await events.next() == .pressed)

        source.giveUp()
        #expect(await events.next() == .released)
    }

    @Test("the source is rebuilt once it has rested")
    @MainActor
    func rebuildsAfterResting() async throws {
        let source = SourceThatGivesUp()
        let monitor = ActivationMonitor(source: source, strokeLeftLock: {}, restSeconds: 0)
        try monitor.start(binding: .optionSpace)
        #expect(source.startCount.withLock { $0 } == 1)

        source.giveUp()
        // The rebuild runs on a detached task; give the run loop a turn to complete it.
        for _ in 0..<50 where source.startCount.withLock({ $0 }) < 2 {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(source.startCount.withLock { $0 } == 2)
    }

    @Test("stopping the monitor cancels a rebuild still resting")
    @MainActor
    func stopCancelsAPendingRebuild() async throws {
        let source = SourceThatGivesUp()
        let monitor = ActivationMonitor(source: source, strokeLeftLock: {}, restSeconds: 3600)
        try monitor.start(binding: .optionSpace)
        source.giveUp()
        monitor.stop()

        // Long enough to notice a rebuild that should not happen; short next to the 3600s rest.
        try await Task.sleep(for: .milliseconds(100))
        #expect(source.startCount.withLock { $0 } == 1)
    }
}
