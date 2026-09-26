// Tests that a stop reached again from inside itself returns at once instead of recursing.
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// A source whose own `stop()` calls back into whatever it is told to, mimicking a deinit reaching through the witness mid-`stop()` — the shape of issue #140's recursive deinit cascade.
private final class ReentrantSource: KeyboardEventSource {
    let calls = Atomic<Int>(0)
    private let reenter = Mutex<(@Sendable () -> Void)?>(nil)

    func start(
        _ deliver: @escaping @Sendable (KeyStroke) -> Void, consumeKeyDown: Bool = false
    ) throws(KeyboardSourceError) {}

    func stop() {
        calls.wrappingAdd(1, ordering: .relaxed)
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
}
