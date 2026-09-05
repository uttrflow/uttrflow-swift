// Owns the Settings window.

import AppKit
import UttrflowDictionary
import UttrflowHistory
import UttrflowSettings
import UttrflowUX
import SwiftUI

/// Owns the Settings window, kept alive between openings; opening it is the one moment the app activates.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsViewModel
    private var window: NSWindow?

    /// `personalisation` has no default: a fresh store here would be a second actor racing over each file.
    init(
        store: any SettingsStore,
        personalisation: any SettingsPersonalisationStore,
        capabilities: SettingsCapabilities = .thisMac(),
        onChange: @escaping (UttrflowSettings.Settings) -> Void = { _ in },
        onReset: @escaping (SettingsReset) -> Void = { _ in },
        onShortcutRecording: @escaping (Bool) -> Void = { _ in }
    ) {
        model = SettingsViewModel(
            store: store, personalisation: personalisation, capabilities: capabilities,
            onChange: onChange, onReset: onReset, onShortcutRecording: onShortcutRecording)
    }

    /// Opens the window and tells it who is signed in; handed over each time, since that can change.
    func show(_ tab: SettingsTab = .general, identity: AccountIdentity? = nil) {
        model.identity = identity
        model.session.tab = tab
        let window = window ?? makeWindow()
        self.window = window
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        model.refreshPersonalisation()

        Task { [model] in
            model.session.capabilities = await SettingsCapabilities.refreshed(
                for: model.session.settings.profile)
        }
    }

    func close() {
        window?.performClose(nil)
    }

    /// Keeps the window hidden rather than released, so the shortcut recorder's state survives.
    func windowWillClose(_ notification: Notification) {
        model.session.cancelRecordingShortcut()
        // The main window's sidebar lights its Settings row while this is open.
        onClose?()
    }

    /// The window has gone; nothing was necessarily altered, but what the interface shows has.
    var onClose: (() -> Void)?

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: SettingsMetrics.windowWidth, height: SettingsMetrics.windowHeight),
            // `.fullSizeContentView`, so the rail runs under the traffic lights as in first-run.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Uttrflow Settings"
        window.titlebarAppearsTransparent = true
        // The rail already says what this is; a title bar repeating it is chrome doing nothing.
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        let hosting = NSHostingView(rootView: SettingsRootView(model: model))
        // See `MainWindowController.makeWindow`: the hosting view would size the window to the tallest pane.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.center()
        return window
    }
}
