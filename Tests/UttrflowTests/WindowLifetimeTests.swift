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
    private func onboardingController() -> OnboardingWindowController {
        let defaults = MemoryDefaults()
        let service = InMemoryAuthenticationService()
        return OnboardingWindowController(
            settingsStore: UserDefaultsSettingsStore(store: defaults),
            record: NeverFinished(),
            account: OnboardingAccountLayer(
                authentication: service,
                profiles: UserDefaultsProfileCache(storage: defaults, verifier: service.verifier),
                local: InMemoryLocalAccountStore()),
            network: AlwaysReachable())
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

    @Test("the Settings window's controller and model are released after every section is drawn five times")
    func settingsWindowReleasesAfterEverySection() throws {
        weak var controller: SettingsWindowController?
        weak var model: SettingsViewModel?
        do {
            let window = SettingsWindowController(
                store: UserDefaultsSettingsStore(store: MemoryDefaults()),
                personalisation: NoPersonalisation(), capabilities: .everything)
            let kept = try #require(stored("model", of: window, as: SettingsViewModel.self))
            controller = window
            model = kept
            for _ in 0..<5 {
                for tab in SettingsTab.allCases {
                    kept.session.tab = tab
                    window.setSuggestionModel(.ready)
                    drawOffscreen(
                        SettingsRootView(model: kept),
                        size: CGSize(width: SettingsMetrics.windowWidth, height: SettingsMetrics.windowHeight)
                    )
                }
            }
        }
        #expect(controller == nil)
        #expect(model == nil)
    }
}
