import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

private final class RefusingSource: KeyboardEventSource {
    private let starts = Mutex(0)

    func start(
        _ deliver: @escaping @Sendable (KeyEvent) -> Void,
        consumeKeyDown: Bool = false
    ) throws(KeyboardSourceError) {
        starts.withLock { $0 += 1 }
        throw .refused
    }

    func stop() {}

    var startCount: Int { starts.withLock { $0 } }
}

@Suite("Activation monitor: a refused tap and Accessibility trust")
struct ActivationMonitorPermissionTests {
    @Test("names stale Accessibility trust when the source refuses a tap")
    @MainActor
    func trustedRefusalNeedsAccessibilityRefresh() {
        let source = RefusingSource()
        let monitor = ActivationMonitor(
            source: source, accessibilityIsGranted: { true }, strokeLeftLock: {})

        #expect(throws: HotkeyError.accessibilityNeedsRefresh) {
            try monitor.start(binding: .optionSpace)
        }
        #expect(source.startCount == 1)
    }

    @Test("keeps the permission error when Accessibility is not trusted")
    @MainActor
    func untrustedRefusalNeedsAccessibilityPermission() {
        let source = RefusingSource()
        let monitor = ActivationMonitor(
            source: source, accessibilityIsGranted: { false }, strokeLeftLock: {})

        #expect(throws: HotkeyError.observationNotPermitted) {
            try monitor.start(binding: .optionSpace)
        }
        #expect(source.startCount == 1)
    }
}
