import AppKit
import UttrflowAccount
import UttrflowCore
import UttrflowPermissions
import UttrflowSettings
import UttrflowSpeech
import UttrflowUX
import Network
import SwiftUI

/// The onboarding window, and everything real that goes behind it.
///
/// The only place first-run onboarding meets the system: the two permission gates, the
/// model store, the settings, and the URLs that open System Settings. Every decision
/// those feed is made in ``OnboardingFlow``, which is why nothing here has a branch in
/// it worth testing.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    /// Called when the user closes the last page, with what they ended up able to do.
    /// Never called for a window the user simply shut, because that user has not
    /// finished and will be asked again next time.
    var onFinish: ((OnboardingReadiness) -> Void)?
    /// The window has gone, however it went.
    ///
    /// Distinct from ``onFinish``, and both are needed. Finishing means the user walked
    /// to the end and said they were done; this means only that the window is no longer
    /// on screen. Somebody who signs in and then shuts the window with the red button has
    /// changed something the rest of the app shows — they have an account now — and
    /// without this the Account page would go on offering them Sign In indefinitely,
    /// because nothing else re-reads the session.
    var onClose: (() -> Void)?

    private let flow: OnboardingFlow
    private let model: OnboardingModel
    private var window: NSWindow?

    /// Everything real that goes behind the window, with a default for each.
    ///
    /// `account` is the backend and the store that believes it, as one value so the two
    /// cannot disagree about which key signs an entitlement. No default, for the same
    /// reason `personalisation` has none in `SettingsWindowController`:
    /// ``OnboardingAccountLayer/development()`` mints a fresh signing key per call, so a
    /// caller that let it default would get a session store rejecting every entitlement
    /// another one had signed — met by the user as a sign-in that succeeds and leaves
    /// them signed out.
    init(
        settingsStore: any SettingsStore,
        modelStore: any SpeechModelStore = FileSystemSpeechModelStore.whisperKit(),
        speechModel: SpeechModel = .default,
        record: any OnboardingRecordStore = UserDefaultsOnboardingRecordStore(),
        account: OnboardingAccountLayer,
        network: any NetworkReachability = SystemNetworkReachability()
    ) {
        flow = OnboardingFlow(
            microphone: MicrophonePermissionGate(),
            accessibility: AccessibilityPermissionGate(),
            installer: SpeechModelInstall(store: modelStore, model: speechModel),
            settingsStore: settingsStore,
            record: record,
            authentication: account.authentication,
            profiles: account.profiles,
            local: account.local,
            network: network,
            // The name macOS knows this Mac's owner by, read here rather than in the
            // flow, so the flow under test is greeting whoever the test says rather than
            // whoever happens to be running it.
            systemName: { NSFullUserName() },
            openBrowser: { url in
                Task { @MainActor in NSWorkspace.shared.open(url) }
            },
            openSystemSettings: { pane in
                Task { @MainActor in OnboardingWindowController.open(pane) }
            },
            now: Date.init
        )
        model = OnboardingModel(flow: flow)
        super.init()
        flow.onFinish = { [weak self] readiness in
            self?.close()
            self?.onFinish?(readiness)
        }
    }

    /// Whether the user has never been through this.
    var isRequired: Bool { flow.isRequired }

    /// Puts the window on screen and brings the app forward.
    ///
    /// A first run is the one moment taking the foreground from another app is right.
    func present(skippingWelcome: Bool = false, askingToSignIn: Bool = false) {
        model.skipsWelcome = skippingWelcome
        model.asksToSignIn = askingToSignIn
        let window = window ?? makeWindow()
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: OnboardingMetrics.windowWidth, height: OnboardingMetrics.windowHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "Welcome to Uttrflow"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.delegate = self
        let hosting = NSHostingView(rootView: OnboardingView(model: model))
        // The onboarding pages are deliberately one fixed size, and a page whose text runs
        // long must not stretch the window under the user mid-flow.
        hosting.sizingOptions = []
        window.contentView = hosting
        return window
    }

    private func close() {
        window?.close()
        window = nil
    }

    /// Both permissions are granted in another application, and macOS says nothing when
    /// that happens. Coming back to this window is the closest thing to a signal there
    /// is, so it is what the flow re-reads on.
    func windowDidBecomeKey(_ notification: Notification) {
        model.refresh()
    }

    /// Whatever closed it — the red button, ``close()`` at the end of the flow, or the
    /// app quitting — the rest of the interface may now be describing a stale world.
    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    /// Where each permission is turned on by hand.
    ///
    /// The mapping lives here rather than in ``UttrflowCore`` for the reason
    /// ``SystemSettingsPane`` gives: the domain holds the pane as a symbol so that it
    /// stays free of anything that knows what a URL is.
    private static func open(_ pane: SystemSettingsPane) {
        let address =
            switch pane {
            case .microphone:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            case .accessibility:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            case .appleIntelligence:
                "x-apple.systempreferences:com.apple.Siri-Settings.extension"
            }
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// The app's model store, narrowed to the one thing onboarding does with it.
private struct SpeechModelInstall: OnboardingModelInstaller {
    let store: any SpeechModelStore
    let model: SpeechModel

    var isInstalled: Bool { store.isInstalled(model) }

    func install(onProgress: @escaping @Sendable (Double) -> Void) async throws(SpeechEngineError) {
        try await store.install(model, onProgress: onProgress)
    }
}
