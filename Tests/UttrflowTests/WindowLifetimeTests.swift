// Every window's model is released with its window, however many times a page is drawn.

import AppKit
import Foundation
import SwiftUI
import Testing
import UttrflowAccount
import UttrflowCore
import UttrflowHistory
import UttrflowSettings
import UttrflowTestSupport
import UttrflowUX

@testable import Uttrflow

/// Bytes in memory, so no test reads or writes the real defaults domain.
private final class MemoryDefaults: KeyValueStore, SessionStorage, @unchecked Sendable {
    private var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? { values[key] }

    func set(_ data: Data?, forKey key: String) { values[key] = data }
}

/// A record of onboarding that says it has never been finished.
private struct NeverFinished: OnboardingRecordStore {
    var hasFinished: Bool { false }

    func recordFinished() {}

    var hasAnsweredClipboard: Bool { false }

    func recordClipboardAnswered() {}
}

/// A connection that is always up, so nothing starts a path monitor.
private struct AlwaysReachable: NetworkReachability {
    var isReachable: Bool { true }
}

/// Personalisation that has nothing to count and nothing to remove.
private struct NoPersonalisation: SettingsPersonalisationStore {
    func personalisation(keeping retention: Retention) async -> SettingsPersonalisation {
        SettingsPersonalisation(learnedWords: 0, addedWords: 0, transcripts: 0)
    }

    func carryOut(_ reset: SettingsReset) async throws(SettingsResetFailure) {}
}

/// The stored property named `label`, read by reflection because the controller keeps it private.
private func stored<T>(_ label: String, of subject: Any, as type: T.Type) -> T? {
    Mirror(reflecting: subject).descendant(label) as? T
}

/// Draws `view` once off screen, so its body runs without a window or an activated app.
@MainActor
private func drawOffscreen(_ view: some View, size: CGSize) {
    autoreleasepool {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
    }
}

@MainActor
@Suite("A window's model is released with its window", .timeLimit(.minutes(1)))
struct WindowLifetimeTests {
    /// The controller the app builds at launch, over stores that touch nothing on this Mac.
    private func onboardingController(settingsStore: (any SettingsStore)? = nil) -> OnboardingWindowController
    {
        let defaults = MemoryDefaults()
        let service = InMemoryAuthenticationService()
        return OnboardingWindowController(
            settingsStore: settingsStore ?? UserDefaultsSettingsStore(store: defaults),
            record: NeverFinished(),
            account: OnboardingAccountLayer(
                authentication: service,
                profiles: UserDefaultsProfileCache(storage: defaults, verifier: service.verifier)),
            network: AlwaysReachable())
    }

    @Test("a second onboarding request reuses the open controller instead of building another")
    func overlappingOnboardingReusesOpenController() {
        var made = 0
        var slot: OnboardingWindowController?
        for _ in 0..<2 {
            let (controller, isNew) = OnboardingWindowController.reusing(slot) {
                made += 1
                return onboardingController()
            }
            if isNew { slot = controller }
            #expect(controller === slot)
        }
        #expect(made == 1)
    }

    @Test("finishing onboarding reloads settings after closing releases its owner")
    func finishingOnboardingKeepsFinishCallback() throws {
        let settingsStore = UserDefaultsSettingsStore(store: MemoryDefaults())
        var saved = Settings()
        saved.showsFloatingButton = false
        settingsStore.save(saved)

        var owner: OnboardingWindowController? = onboardingController(settingsStore: settingsStore)
        let controller = try #require(owner)
        var closeCount = 0
        var finishCount = 0
        var runtimeSettings = Settings()
        owner?.onClose = {
            closeCount += 1
            // Synchronous close can tear down the owner's finish callback before close returns.
            owner?.onFinish = nil
            owner = nil
        }
        owner?.onFinish = { _ in
            finishCount += 1
            runtimeSettings = settingsStore.load()
        }

        controller.finish(.ready) {
            controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        }

        #expect(closeCount == 1)
        #expect(finishCount == 1)
        #expect(owner == nil)
        #expect(runtimeSettings.showsFloatingButton == false)
    }

    @Test("closing onboarding without finishing never invokes its finish callback")
    func closingOnboardingDoesNotFinish() {
        let controller = onboardingController()
        var closeCount = 0
        var finishCount = 0
        controller.onClose = { closeCount += 1 }
        controller.onFinish = { _ in finishCount += 1 }

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        #expect(closeCount == 1)
        #expect(finishCount == 0)
    }

    @Test("the onboarding window is kept on close, so the controller's reference is its only owner")
    func onboardingWindowIsNotReleasedWhenClosed() {
        let window = onboardingController().makeWindow()
        #expect(window.isReleasedWhenClosed == false)
    }

    @Test("a closed onboarding window is freed once, by its last reference")
    func closedOnboardingWindowIsFreedOnce() {
        weak var closed: NSWindow?
        autoreleasepool {
            let window = onboardingController().makeWindow()
            closed = window
            window.close()
        }
        #expect(closed == nil)
    }

    @Test("the flow finish event calls the controller's finish callback")
    func flowFinishCallsController() throws {
        let controller = onboardingController()
        let flow = try #require(stored("flow", of: controller, as: OnboardingFlow.self))
        var finishCount = 0
        controller.onFinish = { _ in finishCount += 1 }

        flow.onFinish?(.ready)

        #expect(finishCount == 1)
    }

    @Test("the onboarding controller built only to read isRequired releases its flow")
    func throwawayOnboardingReleasesItsFlow() {
        weak var flow: OnboardingFlow?
        weak var model: OnboardingModel?
        do {
            let controller = onboardingController()
            #expect(controller.isRequired)
            flow = stored("flow", of: controller, as: OnboardingFlow.self)
            model = stored("model", of: controller, as: OnboardingModel.self)
            #expect(flow != nil)
            #expect(model != nil)
        }
        #expect(flow == nil)
        #expect(model == nil)
    }

    @Test("an onboarding window drawn five times releases its flow")
    func drawnOnboardingReleasesItsFlow() async throws {
        weak var flow: OnboardingFlow?
        weak var model: OnboardingModel?
        do {
            let controller = onboardingController()
            let kept = stored("model", of: controller, as: OnboardingModel.self)
            flow = stored("flow", of: controller, as: OnboardingFlow.self)
            model = kept
            for _ in 0..<5 {
                guard let kept else { break }
                drawOffscreen(
                    OnboardingView(model: kept),
                    size: CGSize(width: OnboardingMetrics.windowWidth, height: OnboardingMetrics.windowHeight)
                )
            }
        }
        // The view's start task holds the flow until it returns, which is a wait and not a cycle.
        try await eventually { flow == nil }
        #expect(flow == nil)
        #expect(model == nil)
    }

    @Test("the main window's controller and model are released after every page is drawn five times")
    func mainWindowReleasesAfterEveryPage() throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        weak var controller: MainWindowController?
        weak var model: MainWindowModel?
        do {
            let window = app.makeMainWindow()
            let kept = try #require(stored("model", of: window, as: MainWindowModel.self))
            controller = window
            model = kept
            for _ in 0..<5 {
                for page in MainTab.allCases {
                    kept.page = page
                    window.update(kept.content)
                    drawOffscreen(
                        MainWindowView(
                            model: kept,
                            onIntent: { [weak window] in window?.onIntent?($0) },
                            onSearch: { [weak window] in window?.onSearch?($0) },
                            onScope: { [weak window] in window?.onScope?($0) },
                            onDraft: { [weak window] in window?.onDraft?() },
                            onToggleSidebar: {}),
                        size: MainMetrics.windowSize)
                }
            }
        }
        #expect(controller == nil)
        #expect(model == nil)
    }

    @Test("the Settings page's controller and model are released after every tab is drawn five times")
    func settingsPageReleasesAfterEveryTab() throws {
        weak var controller: SettingsPageController?
        weak var model: SettingsViewModel?
        do {
            let page = SettingsPageController(
                store: UserDefaultsSettingsStore(store: MemoryDefaults()),
                personalisation: NoPersonalisation(), capabilities: .everything)
            let kept = page.model
            controller = page
            model = kept
            for _ in 0..<5 {
                for tab in SettingsTab.allCases {
                    kept.session.tab = tab
                    page.setSuggestionModel(.ready)
                    drawOffscreen(
                        SettingsPageView(
                            model: kept, diagnostics: DiagnosticsPresenter.page(for: DiagnosticsSnapshot())),
                        size: MainMetrics.windowSize)
                }
            }
        }
        #expect(controller == nil)
        #expect(model == nil)
    }
}
