public import UttrflowCore

/// Reads and requests the Accessibility permission; macOS shows no modal, so a request opens System Settings.
public struct AccessibilityPermissionGate: PermissionGate {
    /// Reads whether this process is trusted.
    private let readStatus: @Sendable () -> PermissionStatus
    /// Opens the Privacy & Security pane for Accessibility.
    private let openSettings: @Sendable () -> Void

    /// Names this gate as the Accessibility permission.
    public let kind: PermissionKind = .accessibility

    /// Substitutes both system calls; the real wiring lives in `AccessibilityPermissionGate+System.swift`.
    init(
        readStatus: @escaping @Sendable () -> PermissionStatus,
        openSettings: @escaping @Sendable () -> Void
    ) {
        self.readStatus = readStatus
        self.openSettings = openSettings
    }

    /// The permission as it stands right now.
    public func status() async -> PermissionStatus {
        readStatus()
    }

    /// Opens System Settings and re-reads, which is almost always still "not granted"; callers re-read later.
    public func request() async -> PermissionStatus {
        let current = readStatus()
        guard current != .granted else { return .granted }
        openSettings()
        return readStatus()
    }
}
