import ServiceManagement
import Synchronization
import Testing

@testable import UttrflowSettings

/// Drives the setting through a stand-in login-item database.
@Suite("LaunchAtLogin")
struct LaunchAtLoginTests {
    /// Whatever macOS refuses with; its contents never matter, as a throw is never the answer.
    private struct SystemRefusal: Error {}

    /// A stand-in database; what a call leaves and whether it throws are independent, like `SMAppService`.
    private func launchAtLogin(
        status: LaunchAtLoginStatus,
        registerLeaves: LaunchAtLoginStatus? = .enabled,
        registerFails: Bool = false,
        unregisterLeaves: LaunchAtLoginStatus? = .disabled,
        unregisterFails: Bool = false,
        onCall: (@Sendable (String) -> Void)? = nil
    ) -> LaunchAtLogin {
        let current = Mutex(status)
        return LaunchAtLogin(
            readStatus: { current.withLock { $0 } },
            register: {
                onCall?("register")
                if let registerLeaves { current.withLock { $0 = registerLeaves } }
                if registerFails { throw SystemRefusal() }
            },
            unregister: {
                onCall?("unregister")
                if let unregisterLeaves { current.withLock { $0 = unregisterLeaves } }
                if unregisterFails { throw SystemRefusal() }
            }
        )
    }

    @Test("reports the status macOS reports", arguments: LaunchAtLoginStatus.allCases)
    func statusMirrorsTheSystem(status: LaunchAtLoginStatus) {
        #expect(launchAtLogin(status: status).status == status)
    }

    @Test("counts itself enabled only when macOS will really start the app")
    func isEnabledOnlyWhenEnabled() {
        for status in LaunchAtLoginStatus.allCases {
            #expect(launchAtLogin(status: status).isEnabled == (status == .enabled))
        }
    }

    @Test("reads the status afresh so a change made in System Settings is not missed")
    func statusIsNotCached() {
        let current = Mutex(LaunchAtLoginStatus.enabled)
        let setting = LaunchAtLogin(
            readStatus: { current.withLock { $0 } },
            register: {},
            unregister: {}
        )

        #expect(setting.isEnabled)
        current.withLock { $0 = .disabled }
        #expect(setting.isEnabled == false)
        #expect(setting.status == .disabled)
    }

    @Test("registers the app when asked to enable it")
    func enableRegisters() {
        let calls = Mutex([String]())
        let setting = launchAtLogin(
            status: .disabled,
            onCall: { call in calls.withLock { $0.append(call) } }
        )

        #expect(setting.enable() == .enabled)
        #expect(calls.withLock { $0 } == ["register"])
    }

    @Test("unregisters the app when asked to disable it")
    func disableUnregisters() {
        let calls = Mutex([String]())
        let setting = launchAtLogin(
            status: .enabled,
            onCall: { call in calls.withLock { $0.append(call) } }
        )

        #expect(setting.disable() == .disabled)
        #expect(calls.withLock { $0 } == ["unregister"])
    }

    /// The case the honesty is for: macOS refused, so the switch must go back to off.
    @Test("leaves the app disabled when macOS refuses to register it")
    func refusedRegistrationIsNotSuccess() {
        let setting = launchAtLogin(status: .disabled, registerLeaves: nil, registerFails: true)

        #expect(setting.enable() == .disabled)
        #expect(setting.isEnabled == false)
    }

    /// An unsigned build: `register()` returns quietly and macOS still has nothing it can launch.
    @Test("reports a registration macOS quietly ignored as unavailable")
    func silentlyIgnoredRegistrationIsNotSuccess() {
        let setting = launchAtLogin(status: .unavailable, registerLeaves: nil)

        #expect(setting.enable() == .unavailable)
        #expect(setting.isEnabled == false)
    }

    /// The throw is "already registered" and the app really will start; believing it turns the switch off.
    @Test("reports an already-registered app as enabled even though registering threw")
    func throwOverAnEnabledStateIsStillEnabled() {
        let setting = launchAtLogin(status: .enabled, registerLeaves: .enabled, registerFails: true)

        #expect(setting.enable() == .enabled)
        #expect(setting.isEnabled)
    }

    /// Registration succeeds and the app still will not start; only the user can finish this, in Settings.
    @Test("reports an app awaiting the user's approval as not yet enabled")
    func approvalPendingIsNotEnabled() {
        let setting = launchAtLogin(status: .disabled, registerLeaves: .requiresApproval)

        #expect(setting.enable() == .requiresApproval)
        #expect(setting.isEnabled == false)
    }

    @Test("reports the app still enabled when macOS refuses to unregister it")
    func refusedUnregistrationIsNotSuccess() {
        let setting = launchAtLogin(status: .enabled, unregisterLeaves: nil, unregisterFails: true)

        #expect(setting.disable() == .enabled)
        #expect(setting.isEnabled)
    }

    @Test("reports an already-unregistered app as disabled even though unregistering threw")
    func throwOverADisabledStateIsStillDisabled() {
        let setting = launchAtLogin(
            status: .disabled,
            unregisterLeaves: .disabled,
            unregisterFails: true
        )

        #expect(setting.disable() == .disabled)
        #expect(setting.isEnabled == false)
    }

    @Test(
        "maps every login-item state macOS defines",
        arguments: [
            (SMAppService.Status.enabled, LaunchAtLoginStatus.enabled),
            (.notRegistered, .disabled),
            (.requiresApproval, .requiresApproval),
            (.notFound, .unavailable),
        ]
    )
    func mapsSystemStatus(system: SMAppService.Status, expected: LaunchAtLoginStatus) {
        #expect(LaunchAtLogin.launchAtLoginStatus(for: system) == expected)
    }

    /// `SMAppService.Status` is an Objective-C enum, so a later macOS can return a case this build lacks.
    @Test("treats a login-item state it does not recognise as disabled")
    func unknownSystemStatusIsDisabled() {
        let future = unsafeBitCast(Int(99), to: SMAppService.Status.self)
        #expect(LaunchAtLogin.launchAtLoginStatus(for: future) == .disabled)
    }
}
