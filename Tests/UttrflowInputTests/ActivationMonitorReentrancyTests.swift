// Tests that a stop reached again from inside itself returns at once, while a stop from another thread still runs.
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// A source whose own `stop()` runs whatever it is told to, the way a release inside a teardown reaches back.
private final class ReentrantSource: KeyboardEventSource {
    let calls = Atomic<Int>(0)
    private let reenter = Mutex<(@Sendable () -> Void)?>(nil)

    func start(
        _ deliver: @escaping @Sendable (KeyEvent) -> Void, consumeKeyDown: Bool = false
    ) throws(KeyboardSourceError) {}

    func stop() {
        let call = calls.wrappingAdd(1, ordering: .relaxed).newValue
        guard call == 1 else { return }
        reenter.withLock { $0 }?()
    }

    func onStop(_ body: @escaping @Sendable () -> Void) {
        reenter.withLock { $0 = body }
    }
}

@Suite("Activation monitor: a stop reached again from inside itself")
struct ActivationMonitorReentrancyTests {
    @Test("a source's stop calling back into the monitor's stop does not recurse")
    @MainActor
    func stopReachedFromWithinItselfReturnsAtOnce() {
        let source = ReentrantSource()
        let monitor = ActivationMonitor(source: source, strokeLeftLock: {})
        source.onStop { monitor.stop() }

        monitor.stop()

        #expect(source.calls.load(ordering: .relaxed) == 1)
    }

    @Test("a stop from another thread while one is running still stops the source")
    @MainActor
    func stopFromAnotherThreadStillRuns() {
        let source = ReentrantSource()
        let monitor = ActivationMonitor(source: source, strokeLeftLock: {})
        source.onStop {
            let done = DispatchSemaphore(value: 0)
            Thread {
                monitor.stop()
                done.signal()
            }.start()
            _ = done.wait(timeout: .now() + 5)
        }

        monitor.stop()

        #expect(source.calls.load(ordering: .relaxed) == 2)
    }
}
