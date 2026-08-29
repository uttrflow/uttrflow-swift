import ServiceManagement

/// What macOS will do with Uttrflow at the next login.
public enum LaunchAtLoginStatus: Sendable, Equatable, CaseIterable {
    /// macOS will start the app when the user next logs in.
    case enabled

    /// macOS knows about the app and will leave it alone.
    case disabled

    /// The app is registered, but macOS will not start it until the user allows it
    /// under Login Items. Asking again cannot move this on; only the user can.
    case requiresApproval

    /// There is no login item for macOS to act on. A build that is not a signed app
    /// bundle reports this, so a developer running from the command line sees an
    /// honest "cannot" rather than a switch that appears to work and never does.
    case unavailable
}

/// Reads and changes whether macOS starts Uttrflow at login.
///
/// The three system calls are injected so that outcomes a test machine cannot be
/// talked into — a user who has refused the app under Login Items, a build macOS will
/// not launch — are exercised without writing to the real login-item database. The
/// `SMAppService` wiring lives in `LaunchAtLogin+System.swift`.
public struct LaunchAtLogin: Sendable {
    private let readStatus: @Sendable () -> LaunchAtLoginStatus
    private let register: @Sendable () throws -> Void
    private let unregister: @Sendable () throws -> Void

    /// Substitutes all three system calls. The `init()` that wires up the real ones lives
    /// alongside them, in `LaunchAtLogin+System.swift`.
    ///
    /// Public so that the *wiring* can be tested and not only this type: the app used to
    /// read "Open Uttrflow at login" and never tell macOS, and nothing could have caught
    /// that without somewhere to stand in for the system.
    public init(
        readStatus: @escaping @Sendable () -> LaunchAtLoginStatus,
        register: @escaping @Sendable () throws -> Void,
        unregister: @escaping @Sendable () throws -> Void
    ) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
    }

    /// Read afresh every time, because the user can change this in System Settings
    /// while the app is running and never tell it.
    public var status: LaunchAtLoginStatus {
        readStatus()
    }

    public var isEnabled: Bool {
        readStatus() == .enabled
    }

    /// Asks macOS to start the app at login, and answers with what it will really do.
    @discardableResult
    public func enable() -> LaunchAtLoginStatus {
        applying(register)
    }

    /// Asks macOS to stop starting the app at login, and answers with what it will
    /// really do.
    @discardableResult
    public func disable() -> LaunchAtLoginStatus {
        applying(unregister)
    }

    /// Makes a change and reports the state that followed it, not the state that was
    /// asked for.
    ///
    /// Neither half of `SMAppService`'s answer means what it looks like. It throws
    /// when the caller already has what it wanted — registering twice — and it returns
    /// without complaint for a build macOS will never actually launch. So the thrown
    /// error is not evidence of failure and its absence is not evidence of success;
    /// only re-reading the status says what happens at the next login.
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
        // A state this build has no name for is certainly not `enabled`, but it is no
        // reason to take the switch away from the user either: `disabled` lets them
        // try, and what they get back afterwards will be the truth.
        @unknown default: .disabled
        }
    }
}
