// The onboarding window and the real permissions, model store and settings behind it.

import AppKit
import UttrflowAccount
import UttrflowCore
import UttrflowPermissions
import UttrflowSettings
import UttrflowSpeech
import UttrflowUX
import Network
import SwiftUI

/// The onboarding window and everything real behind it; every decision is `OnboardingFlow`'s.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    /// Called when the user finishes the last page, never for a window simply shut.
    var onFinish: ((OnboardingReadiness) -> Void)?
    /// The window has gone, however it went; the Account page re-reads the session on it.
    var onClose: (() -> Void)?

    private let flow: OnboardingFlow
    private let model: OnboardingModel
    private var window: NSWindow?

    /// `account` has no default because `OnboardingAccountLayer.development()` mints a fresh key per call.
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
            // Read here, not in the flow, so the flow under test greets whoever the test says.
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

    /// Puts the window on screen and brings the app forward; a first run is the one moment that is right.
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
        // One fixed size, so a long page cannot stretch the window under the user mid-flow.
        hosting.sizingOptions = []
        window.contentView = hosting
        return window
    }

    private func close() {
        window?.close()
        window = nil
    }

    /// Re-reads the permissions, since macOS says nothing when one is granted in System Settings.
    func windowDidBecomeKey(_ notification: Notification) {
        model.refresh()
    }

    /// However the window closed, the rest of the interface may now be describing a stale world.
    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    /// Where each permission is turned on by hand; the domain holds the pane as a symbol, not a URL.
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
