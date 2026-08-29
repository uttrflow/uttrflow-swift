/// A permission the app needs from macOS.
public enum PermissionKind: String, Sendable, Equatable, CaseIterable, Codable {
    case microphone
    case accessibility
}

/// The state of one permission.
public enum PermissionStatus: Sendable, Equatable {
    case notDetermined
    case granted
    case denied
    /// Blocked by policy; asking again will not help.
    case restricted

    public var isGranted: Bool { self == .granted }
}

/// Reads and requests one macOS permission.
///
/// Microphone and Accessibility behave differently underneath — one prompts, the
/// other opens System Settings — but both fit this shape, so onboarding and the
/// settings screen iterate over gates instead of special-casing each permission.
public protocol PermissionGate: Sendable {
    var kind: PermissionKind { get }

    func status() async -> PermissionStatus

    /// Asks the user. Returns the status once the user has answered, or the current
    /// status immediately if the system will not prompt again.
    func request() async -> PermissionStatus
}

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
