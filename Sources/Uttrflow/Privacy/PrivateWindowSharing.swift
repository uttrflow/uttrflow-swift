// Keeps windows with user text out of capture clients that honour AppKit's sharing policy.

import AppKit

enum PrivateWindowSharing {
    static let developmentBundleIdentifier = "com.uttrflow.Uttrflow.dev"
    static let developmentCaptureArgument = "--uttrflow-allow-window-capture"

    /// Hides `window` from capture, or lets AppKit share it when `hidden` is false (the Privacy switch).
    @MainActor
    static func apply(to window: NSWindow, hidden: Bool = true) {
        apply(
            to: window,
            hidden: hidden,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            launchArguments: ProcessInfo.processInfo.arguments)
    }

    @MainActor
    static func apply(
        to window: NSWindow, hidden: Bool = true, bundleIdentifier: String?, launchArguments: [String]
    ) {
        guard hidden else {
            window.sharingType = .readOnly
            return
        }
        guard bundleIdentifier == developmentBundleIdentifier,
            launchArguments.contains(developmentCaptureArgument)
        else {
            window.sharingType = .none
            return
        }
    }
}

extension QuickPanelController {
    /// Follows the Privacy switch for the panel already built; a new panel starts hidden.
    func setHiddenFromCapture(_ hidden: Bool) {
        PrivateWindowSharing.apply(to: panel, hidden: hidden)
    }
}

extension SuggestionPanelController {
    /// Follows the Privacy switch for the overlay already built; a new one starts hidden.
    func setHiddenFromCapture(_ hidden: Bool) {
        PrivateWindowSharing.apply(to: window, hidden: hidden)
    }
}
