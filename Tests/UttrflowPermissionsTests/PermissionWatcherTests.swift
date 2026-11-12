import Synchronization
import Testing
import UttrflowTestSupport

@testable import UttrflowCore
@testable import UttrflowPermissions

/// Drives the watcher over a gate whose answer the test flips.
@MainActor
@Suite("PermissionWatcher", .timeLimit(.minutes(1)))
struct PermissionWatcherTests {
    private final class FlippingGate: PermissionGate {
        let current: Mutex<PermissionStatus>
        init(current: consuming Mutex<PermissionStatus>) { self.current = current }
        var kind: PermissionKind { .accessibility }
        func status() async -> PermissionStatus { current.withLock { $0 } }
        func request() async -> PermissionStatus { current.withLock { $0 } }
    }

    @Test("the first reading is a baseline and tells nobody")
    func baseline() async {
        var told: [PermissionStatus] = []
        let watcher = PermissionWatcher(gate: FlippingGate(current: Mutex(.granted))) { told.append($0) }
        await watcher.read()
        #expect(watcher.status == .granted)
        #expect(told.isEmpty)
    }

    @Test("trust lost and regained is told once each, and an unchanged reading is not told")
    func flips() async {
        let gate = FlippingGate(current: Mutex(.granted))
        var told: [PermissionStatus] = []
        let watcher = PermissionWatcher(gate: gate) { told.append($0) }
        await watcher.read()
        gate.current.withLock { $0 = .denied }
        await watcher.read()
        await watcher.read()
        gate.current.withLock { $0 = .granted }
        await watcher.read()
        #expect(told == [.denied, .granted])
    }

    @Test("a running watcher reads on its own and stops when asked")
    func runs() async throws {
        let gate = FlippingGate(current: Mutex(.granted))
        let told = Mutex<[PermissionStatus]>([])
        let watcher = PermissionWatcher(gate: gate, interval: .milliseconds(5)) { status in
            told.withLock { $0.append(status) }
        }
        watcher.start()
        watcher.start()
        // The first reading is the baseline; flipping the gate before it is taken would tell nobody.
        try await eventually { watcher.status == .granted }
        gate.current.withLock { $0 = .denied }
        try await eventually { !told.withLock { $0.isEmpty } }
        watcher.stop()
        #expect(told.withLock { $0 } == [.denied])
    }
}
