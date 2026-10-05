// Keeps windows with user text out of capture clients that honour AppKit's sharing policy.

import AppKit

enum PrivateWindowSharing {
    static let developmentBundleIdentifier = "com.uttrflow.Uttrflow.dev"
    static let developmentCaptureArgument = "--uttrflow-allow-window-capture"

    @MainActor
    static func apply(to window: NSWindow) {
        apply(
            to: window,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            launchArguments: ProcessInfo.processInfo.arguments)
    }

    @MainActor
    static func apply(to window: NSWindow, bundleIdentifier: String?, launchArguments: [String]) {
        guard bundleIdentifier == developmentBundleIdentifier,
            launchArguments.contains(developmentCaptureArgument)
        else {
            window.sharingType = .none
            return
        }
    }
}
