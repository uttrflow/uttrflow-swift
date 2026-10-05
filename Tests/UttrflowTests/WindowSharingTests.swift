// Tests for keeping user-text windows out of AppKit window sharing.

import AppKit
import Testing
import UttrflowTestSupport

@testable import Uttrflow

private func stored<T>(_ label: String, of subject: Any, as type: T.Type) -> T? {
    Mirror(reflecting: subject).descendant(label) as? T
}

@MainActor
@Suite("What must not be shared as a window", .serialized)
struct WindowSharingTests {
    @Test("the clipboard panel opts out")
    func quickPanelOptsOut() throws {
        let controller = QuickPanelController()
        let window = try #require(stored("panel", of: controller, as: NSWindow.self))

        #expect(window.sharingType == .none)
    }

    @Test("the main window opts out")
    func mainWindowOptsOut() throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let controller = app.makeMainWindow()
        controller.show(.home)
        defer { controller.close() }
        let window = try #require(stored("window", of: controller, as: NSWindow.self))

        #expect(window.sharingType == .none)
    }

    @Test("the suggestion overlay opts out")
    func suggestionOverlayOptsOut() {
        #expect(SuggestionPanelController.shared.window.sharingType == .none)
    }

    @Test("a development window stays private without the capture argument")
    func developmentWindowWithoutArgumentOptsOut() {
        let window = NSWindow()
        PrivateWindowSharing.apply(
            to: window,
            bundleIdentifier: PrivateWindowSharing.developmentBundleIdentifier,
            launchArguments: [])

        #expect(window.sharingType == .none)
    }

    @Test("a release window ignores the development capture argument")
    func releaseWindowIgnoresCaptureArgument() {
        let window = NSWindow()
        PrivateWindowSharing.apply(
            to: window,
            bundleIdentifier: "com.uttrflow.Uttrflow",
            launchArguments: [PrivateWindowSharing.developmentCaptureArgument])

        #expect(window.sharingType == .none)
    }

    @Test("the opt-in leaves development window sharing unchanged")
    func developmentWindowWithArgumentLeavesSharingUnchanged() {
        let window = NSWindow()
        window.sharingType = .readOnly
        PrivateWindowSharing.apply(
            to: window,
            bundleIdentifier: PrivateWindowSharing.developmentBundleIdentifier,
            launchArguments: [PrivateWindowSharing.developmentCaptureArgument])

        #expect(window.sharingType == .readOnly)
    }
}
