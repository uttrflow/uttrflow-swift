import AppKit
import ApplicationServices
import Foundation
import UttrflowCore

/// Wires the gate to macOS.
///
/// Untestable by construction: one call reads a process-wide trust flag, the other
/// opens System Settings. Excluded from the coverage gate for the same reason as the
/// microphone's, and kept short enough that reading it is a sufficient review.
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
