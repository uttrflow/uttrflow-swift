public import UttrflowCore

/// Reads and requests the Accessibility permission that lets text reach other apps.
///
/// Behaves differently from the microphone in a way the product has to respect: macOS
/// never shows a modal for this. Asking opens System Settings and the user grants it
/// there, in their own time, while the app keeps running. So "request" means "point
/// them at it", and the answer arrives later — by them coming back — not from the call.
public struct AccessibilityPermissionGate: PermissionGate {
    private let readStatus: @Sendable () -> PermissionStatus
    private let openSettings: @Sendable () -> Void

    public let kind: PermissionKind = .accessibility

    /// Substitutes both system calls. The public `init()` that wires up the real ones
    /// lives alongside them, in `AccessibilityPermissionGate+System.swift`.
    init(
        readStatus: @escaping @Sendable () -> PermissionStatus,
        openSettings: @escaping @Sendable () -> Void
    ) {
        self.readStatus = readStatus
        self.openSettings = openSettings
    }

    public func status() async -> PermissionStatus {
        readStatus()
    }

    /// Opens System Settings, then reports what is true right now — which is almost
    /// always still "not granted".
    ///
    /// Returning that honestly matters: a caller must not treat this as a yes/no
    /// answer and lock the user out. Onboarding waits and re-reads instead.
    public func request() async -> PermissionStatus {
        let current = readStatus()
        guard current != .granted else { return .granted }
        openSettings()
        return readStatus()
    }
}
