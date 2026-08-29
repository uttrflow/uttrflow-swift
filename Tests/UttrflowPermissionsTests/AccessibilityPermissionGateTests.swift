import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPermissions

@Suite("AccessibilityPermissionGate")
struct AccessibilityPermissionGateTests {
    /// `grantsWhenOpened` stands in for the user walking over to System Settings and
    /// flipping the switch while the app waits.
    private func gate(
        status: PermissionStatus,
        grantsWhenOpened: Bool = false,
        onOpen: (@Sendable () -> Void)? = nil
    ) -> AccessibilityPermissionGate {
        let current = Mutex(status)
        return AccessibilityPermissionGate(
            readStatus: { current.withLock { $0 } },
            openSettings: {
                onOpen?()
                if grantsWhenOpened {
                    current.withLock { $0 = .granted }
                }
            }
        )
    }

    @Test("identifies itself as the accessibility permission")
    func kind() {
        #expect(gate(status: .notDetermined).kind == .accessibility)
    }

    @Test(
        "reports the current status without opening System Settings",
        arguments: [
            PermissionStatus.notDetermined, .granted, .denied, .restricted,
        ]
    )
    func statusIsReadOnly(status: PermissionStatus) async {
        let opened = Mutex(false)
        let gate = gate(status: status, onOpen: { opened.withLock { $0 = true } })

        #expect(await gate.status() == status)
        #expect(opened.withLock { $0 } == false, "reading the status must not open System Settings")
    }

    @Test("leaves System Settings closed when the permission is already granted")
    func doesNotOpenSettingsWhenAlreadyGranted() async {
        let opened = Mutex(false)
        let gate = gate(status: .granted, onOpen: { opened.withLock { $0 = true } })

        #expect(await gate.request() == .granted)
        #expect(opened.withLock { $0 } == false, "there is nothing left to ask for")
    }

    @Test(
        "opens System Settings whenever the permission is not granted yet",
        arguments: [PermissionStatus.notDetermined, .denied, .restricted]
    )
    func opensSettingsWhenNotGranted(status: PermissionStatus) async {
        let opened = Mutex(false)
        let gate = gate(status: status, onOpen: { opened.withLock { $0 = true } })

        _ = await gate.request()
        #expect(opened.withLock { $0 })
    }

    /// macOS shows no modal here, so nobody has answered by the time `request()`
    /// returns — the user grants it in Settings later, in their own time. Reporting
    /// the unchanged "still not granted" is the honest answer, and callers must not
    /// read it as a final "no" and lock the user out of the app. Onboarding is
    /// expected to keep waiting and re-read the status instead.
    @Test(
        "returns the unchanged status because the user answers in Settings later",
        arguments: [PermissionStatus.notDetermined, .denied, .restricted]
    )
    func requestReportsTheStatusAsItStandsRightNow(status: PermissionStatus) async {
        #expect(await gate(status: status).request() == status)
    }

    @Test("reflects the permission the user granted while System Settings was open")
    func statusFollowsAGrantMadeInSettings() async {
        let gate = gate(status: .denied, grantsWhenOpened: true)

        #expect(await gate.status() == .denied)
        #expect(await gate.request() == .granted)
        #expect(await gate.status() == .granted)
    }
}
