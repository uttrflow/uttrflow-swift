import AppKit
import ApplicationServices
import Foundation
import UttrflowCore

/// Wires the gate to macOS; untestable, as it reads a process-wide trust flag and opens System Settings.
extension AccessibilityPermissionGate {
    /// The pane that controls this permission.
    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    /// The gate as the app uses it.
    public init() {
        self.init(
            readStatus: { AXIsProcessTrusted() ? .granted : .denied },
            openSettings: {
                guard let url = AccessibilityPermissionGate.settingsURL else { return }
                NSWorkspace.shared.open(url)
            }
        )
    }
}
