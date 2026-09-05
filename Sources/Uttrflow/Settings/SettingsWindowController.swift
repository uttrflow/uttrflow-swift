import AppKit
import UttrflowDictionary
import UttrflowHistory
import UttrflowSettings
import UttrflowUX
import SwiftUI

/// Owns the Settings window.
///
/// One window, kept alive between openings so that reopening it does not lose which tab
/// the user was on or reload their settings from disk mid-edit. Uttrflow is an accessory
/// app with no Dock icon, so opening this is also the one moment it has to activate:
/// without that the window appears behind whatever the user was working in and cannot
/// take the keyboard, which a shortcut recorder plainly needs.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsViewModel
    private var window: NSWindow?

    /// - Parameters:
    ///   - store: Where the settings are kept. Written to as each change is made.
    ///   - personalisation: The dictionary and the history, so this window can say how
    ///     much of the user is in them before offering to remove it.
    ///   - capabilities: What this Mac can do, so a control with nothing behind it says
    ///     so rather than moving and achieving nothing.
    ///   - onChange: Told about every change that was accepted, so the running app can
    ///     follow it — re-registering the shortcut, moving the floating button.
    ///   - onReset: Told when something was forgotten, so what the rest of the app is
    ///     already holding — the menu bar's copy of the recent dictations, above all —
    ///     is not left showing what the user has just deleted.
    ///   - onShortcutRecording: Told while the shortcut field is listening, so the live
    ///     shortcut can be stood down. A held modifier is passed through to the app by
    ///     that field on purpose, so with Fn bound, choosing a new shortcut also started
    ///     a dictation behind the window.
    ///
    /// `personalisation` has no default, and that is the point. It used to build a fresh
    /// `PersonalDictionaryStore` and `DictationHistoryStore` at the standard paths, with
    /// a comment asking callers to pass their own instead — and the one caller did not.
    /// The result was two actors over each file: two writers racing, and two caches
    /// disagreeing about what was in them. A requirement worth a comment is worth a
    /// compiler error.
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

    /// Opens the window, and tells it who is signed in.
    ///
    /// Handed over on every opening rather than held: the app already re-reads the
    /// capabilities and the personalisation here for the same reason, and somebody can
    /// have signed out — or signed in as somebody else — between one opening and the next.
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

    /// Released on close would take the view model's unsaved shortcut recording with it,
    /// so the window is kept and merely hidden.
    func windowWillClose(_ notification: Notification) {
        model.session.cancelRecordingShortcut()
        // The main window's sidebar lights its Settings row while this window is open, so
        // it has to be told when it is not.
        onClose?()
    }

    /// The window has gone. Distinct from a settings change: nothing was necessarily
    /// altered, but what the rest of the interface should show has.
    var onClose: (() -> Void)?

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: SettingsMetrics.windowWidth, height: SettingsMetrics.windowHeight),
            // `.fullSizeContentView` so the rail runs under the traffic lights, as it
            // does in first-run. Without it the title bar is a strip of the system's own
            // grey across the top of a window whose left-hand quarter is teal — which is
            // exactly the seam between "our design" and "a Mac dialogue" this window was
            // redrawn to remove.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Uttrflow Settings"
        window.titlebarAppearsTransparent = true
        // As on the main window: the rail under the lights already says what this is, and
        // a title bar that repeats it is a strip of chrome doing nothing.
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        let hosting = NSHostingView(rootView: SettingsRootView(model: model))
        // See `MainWindowController.makeWindow`: left to itself, the hosting view resizes
        // the window to whatever the tallest pane wants.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.center()
        return window
    }
}
