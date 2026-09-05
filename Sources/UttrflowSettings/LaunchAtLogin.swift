// The launch-at-login setting: the states macOS reports and the type that reads and changes them.
import ServiceManagement

/// What macOS will do with Uttrflow at the next login.
public enum LaunchAtLoginStatus: Sendable, Equatable, CaseIterable {
    /// macOS will start the app when the user next logs in.
    case enabled

    /// macOS knows about the app and will leave it alone.
    case disabled

    /// Registered, but not started until the user allows it under Login Items; only they can move this on.
    case requiresApproval

    /// No login item exists, as for a build that is not a signed app bundle; the switch honestly cannot work.
    case unavailable
}

/// Reads and changes whether macOS starts Uttrflow at login. See Docs/core-settings-launch-at-login.md.
public struct LaunchAtLogin: Sendable {
    /// Reads the login item's current state.
    private let readStatus: @Sendable () -> LaunchAtLoginStatus
    /// Asks macOS to start the app at login.
    private let register: @Sendable () throws -> Void
    /// Asks macOS to stop starting the app at login.
    private let unregister: @Sendable () throws -> Void

    /// Substitutes all three system calls; public so the wiring in `LaunchAtLogin+System.swift` is testable.
    public init(
        readStatus: @escaping @Sendable () -> LaunchAtLoginStatus,
        register: @escaping @Sendable () throws -> Void,
        unregister: @escaping @Sendable () throws -> Void
    ) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
    }

    /// Read afresh every time, since the user can change it in System Settings without telling the app.
    public var status: LaunchAtLoginStatus {
        readStatus()
    }

    public var isEnabled: Bool {
        status == .enabled
    }

    /// Asks macOS to start the app at login, and answers with what it will really do.
    @discardableResult
    public func enable() -> LaunchAtLoginStatus {
        applying(register)
    }

    /// Asks macOS to stop starting the app at login, and answers with what it will really do.
    @discardableResult
    public func disable() -> LaunchAtLoginStatus {
        applying(unregister)
    }

    /// Applies a change, then re-reads the status. See Docs/core-settings-launch-at-login.md.
    private func applying(_ change: @Sendable () throws -> Void) -> LaunchAtLoginStatus {
        try? change()
        return readStatus()
    }

    /// Maps the system's login-item states onto the product's.
    static func launchAtLoginStatus(for status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        // An unknown state is not `enabled`; `disabled` keeps the switch usable and the re-read is the truth.
        @unknown default: .disabled
        }
    }
}
