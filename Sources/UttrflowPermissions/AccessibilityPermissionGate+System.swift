import ApplicationServices
import UttrflowCore

/// Wires the gate to macOS; untestable, as it reads a process-wide trust flag and opens System Settings.
extension AccessibilityPermissionGate {
    /// The gate as the app uses it.
    public init() {
        self.init(
            readStatus: { AXIsProcessTrusted() ? .granted : .denied },
            openSettings: { SystemSettingsOpener().open(.accessibility) }
        )
    }
}
