// The entry point.

import AppKit
import Foundation
import OSLog
import UttrflowAccount
import UttrflowCore
import UttrflowLocalModel
import UttrflowPipeline
import UttrflowPredict
import UttrflowSettings
import UttrflowUX

/// The app, owning nothing but the objects it wires together.
@main
enum UttrflowApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let testContainer = ProcessInfo.processInfo.environment["UTTRFLOW_TEST_CONTAINER"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let container = testContainer ?? .applicationSupportDirectory
        let testDefaultsSuite = testContainer.map { "com.uttrflow.UITests.\($0.lastPathComponent)" }
        let settingsStore = UserDefaultsSettingsStore(
            store: SystemUserDefaults(suiteName: testDefaultsSuite))
        let onboardingRecordStore = UserDefaultsOnboardingRecordStore(
            store: SystemUserDefaults(suiteName: testDefaultsSuite))
        if testContainer != nil {
            var settings = Settings.default
            settings.opensAtLogin = false
            settings.checksForUpdatesAutomatically = false
            settings.installsUpdatesAutomatically = false
            settingsStore.save(settings)
            onboardingRecordStore.recordFinished()
        }
        let account =
            testContainer.map { _ in
                OnboardingAccountLayer(
                    authentication: InMemoryAuthenticationService(), profiles: UITestProfileCache())
            } ?? OnboardingAccountLayer.forThisBuild()
        let loginItem =
            testContainer.map { _ in
                LaunchAtLogin(readStatus: { .unavailable }, register: {}, unregister: {})
            } ?? LaunchAtLogin()
        // Before any model or keyboard monitor exists, so a second copy never builds either.
        guard let instance = claimTheOnlyInstance(in: container) else { exit(0) }
        let (reloads, reported) = AsyncStream<IdleReload>.makeStream()
        // One model both validates a remembered suggestion and invents one where there is none; its weights are fetched when the feature is first built, never at launch.
        let local = MLXCandidateScorer(
            model: .configured(UserDefaults.standard.string(forKey: LocalModel.configurationKey)))
        let model = IdleReleasingModel(
            model: local,
            idleAfter: IdleRelease.window(physicalMemory: ProcessInfo.processInfo.physicalMemory),
            onReload: { reported.yield($0) })
        // Every use is discretionary: utility priority, and no pass in Low Power Mode, under thermal pressure or while dictating.
        let generating = DiscretionaryGenerator(
            model,
            mayRun: {
                EnergyConditions.current().allowsDiscretionaryWork && !DictationInProgress.shared.isDictating
            })
        let scoring = DiscretionaryModel(
            model,
            mayRun: {
                EnergyConditions.current().allowsDiscretionaryWork && !DictationInProgress.shared.isDictating
            })
        let delegate = AppDelegate(
            container: container,
            loginItem: loginItem,
            settingsStore: settingsStore,
            onboardingRecordStore: onboardingRecordStore,
            account: account,
            scoring: scoring, generating: generating,
            prepareModel: { onProgress in try await scoring.prepare(onProgress: onProgress) },
            releaseModel: { await scoring.release() },
            allowModelReload: { await scoring.allowReloadAfterRelease() },
            encryptedStore: EncryptedStore(markerURL: EncryptedStore.productionLegacyMigrationMarkerURL()),
            localTidier: local)
        application.delegate = delegate
        // A reload after an idle release is shown where the user is looking, not only in Settings.
        Task { @MainActor in
            for await event in reloads { delegate.suggestionModelReloaded(event) }
        }
        // A reload that finds the weights gone asks for them again in Settings rather than fetching them unasked.
        Task { [weak delegate] in
            await scoring.whenReloadFails { Task { @MainActor in delegate?.suggestionModelWentMissing() } }
        }
        // Regular, not accessory: Uttrflow has a Dock icon and its window opens at launch.
        application.setActivationPolicy(.regular)
        // A regular app with no main menu loses ⌘C, ⌘V, ⌘A and ⌘Z in every text field.
        application.mainMenu = MainMenu.build()
        // Keep all lock descriptors alive for the full event loop.
        withExtendedLifetime(instance) { application.run() }
    }

    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "launch")

    /// The lock set retained for the duration of the application event loop.
    private struct InstanceLocks {
        let store: SingleInstanceLock
        let coordination: SingleInstanceLock
        let legacyStoreGuards: [SingleInstanceLock]
    }

    @MainActor
    private static func claimTheOnlyInstance(in container: URL) -> InstanceLocks? {
        let identifier = Bundle.main.bundleIdentifier
        // Acquire shared coordination before per-build store locks so a loser cannot make the winner exit.
        guard
            let coordination = acquireOrExplain(
                at: SingleInstanceLock.coordinationFile(in: container), identifier: identifier)
        else {
            return nil
        }
        guard
            let store = acquireOrExplain(
                at: SingleInstanceLock.defaultFile(in: container), identifier: identifier)
        else {
            return nil
        }
        guard
            let legacyStoreGuards = guardAgainstOlderBuilds(
                differentFrom: identifier, currentStoreFile: SingleInstanceLock.defaultFile(in: container),
                in: container)
        else {
            return nil
        }
        return InstanceLocks(
            store: store, coordination: coordination, legacyStoreGuards: legacyStoreGuards)
    }

    /// Guards older running builds and current-protocol startup losers without exiting the coordinator winner.
    @MainActor
    private static func guardAgainstOlderBuilds(
        differentFrom identifier: String?, currentStoreFile: URL, in directory: URL
    ) -> [SingleInstanceLock]? {
        let me = ProcessInfo.processInfo.processIdentifier
        let otherIdentifiers = Set(
            NSWorkspace.shared.runningApplications.filter(isUttrflow).compactMap(\.bundleIdentifier).filter {
                $0 != identifier
            })
        var guards: [SingleInstanceLock] = []
        for otherIdentifier in otherIdentifiers {
            let otherStoreFile = SingleInstanceLock.defaultFile(in: directory, for: otherIdentifier)
            // Unknown IDs can share the production folder; our own store lock already covers it.
            guard otherStoreFile.standardizedFileURL != currentStoreFile.standardizedFileURL else {
                continue
            }
            switch SingleInstanceLock.acquire(at: otherStoreFile) {
            case .acquired(let lock):
                guards.append(lock)
                // A free lock proves nothing about a build that predates it, so judge the peer by whether it stays running.
                if let peer = runningPeer(otherIdentifier, excluding: me),
                    LocklessPeer.outlasts(isRunning: { !peer.isTerminated })
                {
                    explainConflict(with: peer)
                    return nil
                }
            case .heldElsewhere:
                if let running = runningPeer(otherIdentifier, excluding: me) {
                    explainConflict(with: running)
                } else {
                    explainLockFailure()
                }
                return nil
            case .unavailable:
                explainLockFailure()
                return nil
            }
        }
        return guards
    }

    /// A live process of `identifier` other than `me`.
    @MainActor
    private static func runningPeer(_ identifier: String, excluding me: pid_t) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier != me && $0.bundleIdentifier == identifier && !$0.isTerminated
        }
    }

    @MainActor
    private static func acquireOrExplain(at file: URL, identifier: String?) -> SingleInstanceLock? {
        var outcome = SingleInstanceLock.acquire(at: file)
        if case .heldElsewhere = outcome {
            if let sameBuild = otherInstance(identifier: identifier) {
                log.notice("Another copy with this identifier is running; handing off and exiting")
                explainSameBuildHandoff(to: sameBuild)
                return nil
            }
            if let differentBuild = otherUttrflowInstance(differentFrom: identifier) {
                explainConflict(with: differentBuild)
                return nil
            }
            outcome = SingleInstanceLock.acquire(at: file, waitingUpTo: .seconds(5))
        }
        switch outcome {
        case .acquired(let lock):
            return lock
        case .unavailable(let code):
            log.error("Could not take a required single-instance lock: \(code)")
            explainLockFailure()
            return nil
        case .heldElsewhere:
            if let running = otherInstance(identifier: identifier) {
                explainSameBuildHandoff(to: running)
            } else if let running = otherUttrflowInstance(differentFrom: identifier) {
                explainConflict(with: running)
            } else {
                explainLockFailure()
            }
            return nil
        }
    }

    /// Another running process with this bundle identifier, from whatever path it was started.
    @MainActor
    private static func otherInstance(identifier: String?) -> NSRunningApplication? {
        guard let identifier else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first { $0.processIdentifier != me && !$0.isTerminated }
    }

    /// Another running app in the Uttrflow identifier family with a different identifier.
    @MainActor
    private static func otherUttrflowInstance(differentFrom identifier: String?) -> NSRunningApplication? {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier != me && !$0.isTerminated && $0.bundleIdentifier != identifier
                && isUttrflow($0)
        }
    }

    /// Whether a running app is a build of Uttrflow, read from its identifier or, outside the prefix, its executable.
    private static func isUttrflow(_ app: NSRunningApplication) -> Bool {
        UttrflowBuildIdentity.isUttrflow(
            app.bundleIdentifier, executableName: app.executableURL?.lastPathComponent)
    }

    @MainActor
    private static func explainConflict(with running: NSRunningApplication) {
        let thisName = buildName
        let otherName = running.localizedName ?? running.bundleIdentifier ?? "another Uttrflow build"
        var detail =
            "Both builds listen for a system-wide shortcut and use the microphone. Quit one build before launching \(thisName)."
        if let fallback = productionFallbackExplanation(for: thisName) {
            detail += "\n\n\(fallback)"
        }
        let visibleOtherName =
            otherName == thisName
            ? "\(otherName) (\(running.bundleIdentifier ?? "unknown identifier"))" : otherName
        showLaunchAlert(
            title: "\(thisName) cannot run beside \(visibleOtherName)", detail: detail)
    }

    @MainActor
    private static func explainSameBuildHandoff(to running: NSRunningApplication) {
        if let fallback = productionFallbackExplanation(for: buildName) {
            let otherName = running.localizedName ?? running.bundleIdentifier ?? buildName
            let visibleOtherName =
                otherName == buildName
                ? "\(otherName) (\(running.bundleIdentifier ?? "unknown identifier"))" : otherName
            showLaunchAlert(
                title: "\(buildName) cannot start beside \(visibleOtherName)",
                detail:
                    "Another copy is already running. This launch is exiting and will bring it forward.\n\n\(fallback)"
            )
        }
        handOff(to: running)
    }

    @MainActor
    private static func explainLockFailure() {
        var detail =
            "Uttrflow could not confirm that it is the only build using the shortcut and microphone, so it has exited. Check that another Uttrflow process is not still running, then try again."
        if let fallback = productionFallbackExplanation(for: buildName) {
            detail += "\n\n\(fallback)"
        }
        showLaunchAlert(title: "Uttrflow could not start safely", detail: detail)
    }

    private static func productionFallbackExplanation(for name: String) -> String? {
        let identifier = Bundle.main.bundleIdentifier
        guard
            identifier != LocalStore.productionIdentifier,
            UttrflowBuildIdentity.usesProductionFolder(identifier)
        else { return nil }
        let identifierText = identifier ?? "a missing bundle identifier"
        return
            "\(name) uses the production data folder because \(identifierText) is not a development variant. Set the identifier to \(LocalStore.productionIdentifier).<variant> to isolate its data."
    }

    private static var buildName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Uttrflow"
    }

    @MainActor
    private static func showLaunchAlert(title: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }

    /// Brings the running copy forward and asks it to reopen, which shows its window when none is visible.
    @MainActor
    private static func handOff(to running: NSRunningApplication) {
        guard let bundle = running.bundleURL else {
            running.activate()
            return
        }
        let done = DispatchSemaphore(value: 0)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { _, error in
            if error != nil { running.activate() }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 3)
    }
}

/// A signed-in account fixture that keeps UI tests away from the developer's keychain and server.
private struct UITestProfileCache: ProfileCache {
    func load() -> Profile? { Self.profile }

    func save(_ profile: Profile) throws(AccountError) {}

    func clear() {}

    private static let profile: Profile = {
        let account = Account(
            identifier: "ui-test", displayName: "UI Test", emailAddress: "ui-test@example.invalid",
            provider: .google)
        let entitlement = Entitlement(
            account: account, plan: .pro, expiresAt: .distantFuture, signature: "ui-test")
        return Profile(
            account: account,
            subscription: Profile.Subscription(
                plan: .pro, status: .active, currentPeriodEnd: nil, effectivePlan: .pro,
                limits: Profile.Limits(monthlyMinutes: nil, customDictionaryEntries: nil)),
            devices: [], entitlement: entitlement, fetchedAt: .distantPast)
    }()
}
