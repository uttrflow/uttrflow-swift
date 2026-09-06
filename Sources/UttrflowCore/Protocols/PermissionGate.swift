// The permissions the app needs and the gate protocol that reads and requests one.

/// A permission the app needs from macOS.
public enum PermissionKind: String, Sendable, Equatable, CaseIterable, Codable {
    /// Microphone access, to record.
    case microphone
    /// Accessibility trust, to insert text into other apps.
    case accessibility
}

/// The state of one permission.
public enum PermissionStatus: Sendable, Equatable {
    /// Never asked.
    case notDetermined
    /// Granted.
    case granted
    /// Refused by the user; System Settings can change it.
    case denied
    /// Blocked by policy; asking again will not help.
    case restricted

    public var isGranted: Bool { self == .granted }
}

/// Reads and requests one macOS permission, so onboarding iterates over gates instead of special-casing each.
public protocol PermissionGate: Sendable {
    /// Which permission this gate is for.
    var kind: PermissionKind { get }

    /// The current state, without prompting.
    func status() async -> PermissionStatus

    /// Asks the user and returns the answer, or the current status at once when the system will not prompt.
    func request() async -> PermissionStatus
}

/// What each permission maps to in System Settings and in the failure vocabulary.
extension PermissionKind {
    /// Where the user goes to change this permission by hand.
    public var settingsPane: SystemSettingsPane {
        switch self {
        case .microphone: .microphone
        case .accessibility: .accessibility
        }
    }

    /// The failure raised when this permission is missing.
    public var failure: PermissionError {
        switch self {
        case .microphone: .microphoneDenied
        case .accessibility: .accessibilityNotTrusted
        }
    }
}
