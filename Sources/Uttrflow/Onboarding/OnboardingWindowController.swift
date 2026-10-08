// The onboarding window and the real permissions, model store and settings behind it.

import AppKit
import UttrflowAccount
import UttrflowCore
import UttrflowPermissions
import UttrflowPipeline
import UttrflowSettings
import UttrflowSpeech
import UttrflowUX
import Network
import SwiftUI

enum OnboardingPresentationBehavior: Equatable {
    case standard
    case developmentLaunch
}

/// The onboarding window and everything real behind it; every decision is `OnboardingFlow`'s.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    /// Called when the user finishes the last page, never for a window simply shut.
    var onFinish: ((OnboardingReadiness) -> Void)?
    /// The window has gone, however it went; the Account page re-reads the session on it.
    var onClose: (() -> Void)?
    /// Called as soon as a sign-in's profile is kept, before the setup pages after it.
    var onSignIn: (() -> Void)?
    /// Applies onboarding choices to the running app.
    var onSettingsChange: ((UttrflowSettings.Settings) -> Void)? {
        didSet { flow.onSettingsChange = onSettingsChange }
    }

    private let flow: OnboardingFlow
    private let model: OnboardingModel
    private let signsInAsStandIn: Bool
    private var window: NSWindow?

    /// `account` has no default because `OnboardingAccountLayer.development()` mints a fresh key per call.
    init(
        settingsStore: any SettingsStore,
        installer: any OnboardingModelInstaller = SpeechModelInstall(
            store: FileSystemSpeechModelStore.whisperKit(), model: .default),
        record: any OnboardingRecordStore = UserDefaultsOnboardingRecordStore(),
        account: OnboardingAccountLayer,
        network: any NetworkReachability = SystemNetworkReachability()
    ) {
        signsInAsStandIn = account.authentication.signsInAsStandIn
        flow = OnboardingFlow(
            microphone: MicrophonePermissionGate(),
            accessibility: AccessibilityPermissionGate(),
            installer: installer,
            settingsStore: settingsStore,
            record: record,
            authentication: account.authentication,
            profiles: account.profiles,
            network: network,
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
        flow.onSignIn = { [weak self] in
            self?.onSignIn?()
            // The browser has the screen, so the welcome is brought forward rather than left behind it.
            self?.bringForward()
        }
        flow.onFinish = { [weak self] readiness in
            guard let self else { return }
            self.finish(readiness) { self.close() }
        }
    }

    func finish(_ readiness: OnboardingReadiness, closing close: () -> Void) {
        let onFinish = onFinish
        close()
        onFinish?(readiness)
    }

    /// The controller still open if there is one, so at most one onboarding window exists at a time.
    static func reusing(
        _ existing: OnboardingWindowController?, orMaking make: () -> OnboardingWindowController
    ) -> (controller: OnboardingWindowController, isNew: Bool) {
        if let existing { return (existing, false) }
        return (make(), true)
    }

    /// Whether the window is on screen, which a closed or minimised one is not.
    var isVisible: Bool { window?.isVisible == true }

    /// Whether the user has never been through this.
    var isRequired: Bool { flow.isRequired }

    /// Starts development sign-in only when this build uses the local stand-in.
    func signInAsStandInIfNeeded() {
        guard signsInAsStandIn else { return }
        Task { await flow.perform(.signIn(.google)) }
    }

    /// Closes launch onboarding when a completed setup only needed a new stand-in session.
    func closeIfNotRequired() {
        guard !flow.isRequired else { return }
        close()
    }

    /// Puts the window on screen and brings the app forward; a first run is the one moment that is right.
    func present() {
        let window = window ?? makeWindow()
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }

    /// Brings the open window and the app to the front without moving the window.
    func bringForward() {
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }

    /// Builds the window without showing it, internal so a test can read how it is configured.
    func makeWindow() -> NSWindow {
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
        // Owned by `window`, so closing must not release it a second time under a running close animation.
        window.isReleasedWhenClosed = false
        // Dark in every appearance, so the window's own buttons sit on the aurora the way it is drawn.
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(rgb: BrandPalette.Onboarding.windowGround)
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

    /// Puts the flow back on its sign-in page, whichever page a sign-out found it on.
    func signedOut() {
        model.signedOut()
    }

    /// Shows a dictation on the last page, where the first try fills the page's own field.
    func dictationChanged(to state: DictationState) {
        guard let trial = Self.trial(for: state) else { return }
        model.tried(trial)
    }

    /// What a dictation's state means for the first try, or `nil` for a state that changes nothing.
    nonisolated static func trial(for state: DictationState) -> OnboardingTrial? {
        switch state {
        case .recording: .listening
        case .inserted(let outcome): .heard(outcome.text)
        case .failed(.stillLoading): .stillLoading
        case .failed(let failure): .heard(failure.transcript ?? "")
        case .idle, .transcribing, .tidying, .inserting, .discarded: nil
        }
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
        SystemSettingsOpener().open(pane)
    }
}

/// The app's model store, narrowed to the one thing onboarding does with it.
struct SpeechModelInstall: OnboardingModelInstaller {
    let store: any SpeechModelStore
    let model: SpeechModel

    var isInstalled: Bool { store.isInstalled(model) }

    func install(onProgress: @escaping @Sendable (Double) -> Void) async throws(SpeechEngineError) {
        try await store.install(model, onProgress: onProgress)
    }
}
