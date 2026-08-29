import AVFoundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPermissions

@Suite("MicrophonePermissionGate")
struct MicrophonePermissionGateTests {
    private func gate(
        status: PermissionStatus,
        grants: Bool = true,
        onRequest: (@Sendable () -> Void)? = nil
    ) -> MicrophonePermissionGate {
        let current = Mutex(status)
        return MicrophonePermissionGate(
            readStatus: { current.withLock { $0 } },
            requestAccess: {
                onRequest?()
                current.withLock { $0 = grants ? .granted : .denied }
                return grants
            }
        )
    }

    @Test("identifies itself as the microphone permission")
    func kind() {
        #expect(MicrophonePermissionGate().kind == .microphone)
    }

    @Test(
        "maps every system authorisation state",
        arguments: [
            (AVAuthorizationStatus.notDetermined, PermissionStatus.notDetermined),
            (.authorized, .granted),
            (.denied, .denied),
            (.restricted, .restricted),
        ]
    )
    func mapsSystemStatus(system: AVAuthorizationStatus, expected: PermissionStatus) {
        #expect(MicrophonePermissionGate.permissionStatus(for: system) == expected)
    }

    /// A future macOS could add a state. `init?(rawValue:)` rejects values it does
    /// not know, so the bit pattern is forced to reach the `@unknown default` arm and
    /// prove an unrecognised state fails closed rather than falling through.
    @Test("treats an authorisation state it does not recognise as denied")
    func unknownStatusIsDenied() {
        let future = unsafeBitCast(Int(99), to: AVAuthorizationStatus.self)
        #expect(MicrophonePermissionGate.permissionStatus(for: future) == .denied)
    }

    @Test(
        "reports the current status without prompting",
        arguments: [
            PermissionStatus.notDetermined, .granted, .denied, .restricted,
        ]
    )
    func statusIsReadOnly(status: PermissionStatus) async {
        let asked = Mutex(false)
        let gate = gate(status: status, onRequest: { asked.withLock { $0 = true } })

        #expect(await gate.status() == status)
        #expect(asked.withLock { $0 } == false, "reading the status must not prompt")
    }

    @Test("prompts only when the user has not decided yet")
    func promptsWhenUndecided() async {
        let asked = Mutex(false)
        let gate = gate(status: .notDetermined, onRequest: { asked.withLock { $0 = true } })

        #expect(await gate.request() == .granted)
        #expect(asked.withLock { $0 })
    }

    @Test("records a refusal")
    func recordsRefusal() async {
        #expect(await gate(status: .notDetermined, grants: false).request() == .denied)
    }

    /// macOS prompts once and never again, so asking a user who has already decided
    /// would silently do nothing. Returning their decision is the honest answer.
    @Test(
        "returns the existing decision instead of pretending to prompt",
        arguments: [PermissionStatus.granted, .denied, .restricted]
    )
    func doesNotRepromptAfterADecision(status: PermissionStatus) async {
        let asked = Mutex(false)
        let gate = gate(status: status, onRequest: { asked.withLock { $0 = true } })

        #expect(await gate.request() == status)
        #expect(asked.withLock { $0 } == false)
    }

    @Test("reflects the new status after the user answers the prompt")
    func statusFollowsTheAnswer() async {
        let gate = gate(status: .notDetermined)

        #expect(await gate.status() == .notDetermined)
        _ = await gate.request()
        #expect(await gate.status() == .granted)
    }
}
