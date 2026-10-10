// Sparkle wiring, and when a staged update may install.

import AppKit
import Sparkle
import UttrflowCore
import UttrflowUX

/// The Sparkle settings that come from the two independent update preferences.
@MainActor
protocol UpdateSettingsTarget: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
}

extension SPUUpdater: UpdateSettingsTarget {}

/// Applies the saved choices through the same mapping at launch and in focused tests.
@MainActor
enum UpdateSettingsMapping {
    static func configure(
        checksAutomatically: Bool,
        installsAutomatically: Bool,
        to updater: any UpdateSettingsTarget
    ) {
        updater.automaticallyChecksForUpdates = checksAutomatically
        updater.automaticallyDownloadsUpdates = installsAutomatically
    }

    static func setChecksAutomatically(_ isOn: Bool, on updater: any UpdateSettingsTarget) {
        updater.automaticallyChecksForUpdates = isOn
    }

    static func setInstallsAutomatically(_ isOn: Bool, on updater: any UpdateSettingsTarget) {
        updater.automaticallyDownloadsUpdates = isOn
    }
}

/// Decides when Sparkle may check (`UpdateStartupGate`) and replace the bundle (`UpdateGate`). See Docs/app-updates.md.
@MainActor
final class UpdateController: NSObject {
    /// Sparkle's own controller; `startUpdater()` waits on `startupGate` so no check competes with the model load.
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    /// Asks what the app is doing, because a quiet app reports nothing at the moment the gate opens.
    private let activity: @MainActor () -> UpdateActivity

    private var gate = UpdateGate()

    /// Sparkle's install-now handle, held from staging until the app is quiet enough to take it.
    private var installNow: (() -> Void)?

    /// Wakes the controller when the gate is due to open, since a quiet app never reports again on its own.
    private var wakeUp: Task<Void, Never>?

    /// When Sparkle's `startUpdater()` may run; see ``UpdateStartupGate``.
    private var startupGate = UpdateStartupGate()

    nonisolated private let requestActivity = UpdateRequestActivity()

    /// How far along an update is, published so the menu bar can redraw from it.
    private(set) var progress: UpdateProgress = .idle {
        didSet {
            guard progress != oldValue else { return }
            onProgressChanged?()
        }
    }

    /// Called whenever ``progress`` changes, so the menu bar can be redrawn.
    var onProgressChanged: (() -> Void)?

    var updater: SPUUpdater { controller.updater }

    init(activity: @escaping @MainActor () -> UpdateActivity) {
        self.activity = activity
        super.init()
    }

    /// Whether this build can update itself: a feed and a real key; `nonisolated` for the settings probe.
    nonisolated static var isConfigured: Bool {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let url = URL(string: feed), UpdateFeed.isAcceptable(url)
        else { return false }
        // A placeholder key fails closed: Sparkle would install whatever the feed handed it.
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            isPublicKey(key)
        else { return false }
        // Checks the archive against the key before it is unpacked. See Docs/releasing.md ("Updating").
        return Bundle.main.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool == true
    }

    /// Whether `key` is base64 for a 32-byte Ed25519 public key that is not all zeros.
    nonisolated static func isPublicKey(_ key: String) -> Bool {
        guard let bytes = Data(base64Encoded: key), bytes.count == 32 else { return false }
        return bytes.contains { $0 != 0 }
    }

    /// Configures Sparkle; an automatic check itself waits for ``modelLoadingSettled()``.
    func begin(checksAutomatically: Bool, installsAutomatically: Bool) {
        guard Self.isConfigured, !startupGate.isConfigured else { return }
        startupGate.configure()
        UpdateSettingsMapping.configure(
            checksAutomatically: checksAutomatically,
            installsAutomatically: installsAutomatically,
            to: updater)
        if startupGate.mayStartAutomatically() { controller.startUpdater() }
    }

    /// The speech model has settled — loaded, failed, or was never installed; safe before or after `begin`.
    func modelLoadingSettled() {
        startupGate.settle()
        if startupGate.mayStartAutomatically() { controller.startUpdater() }
    }

    /// The user changed the switch in Settings.
    func setInstallsAutomatically(_ isOn: Bool) {
        guard startupGate.isConfigured else { return }
        UpdateSettingsMapping.setInstallsAutomatically(isOn, on: updater)
    }

    /// The user changed the automatic-check switch in Settings.
    func setChecksAutomatically(_ isOn: Bool) {
        guard startupGate.isConfigured else { return }
        UpdateSettingsMapping.setChecksAutomatically(isOn, on: updater)
    }

    /// Re-reads what the app is doing and acts on it; called on every redraw and from the wake-up.
    func refresh(at now: Date = Date()) {
        gate.note(activity(), at: now)
        installIfTheMomentIsRight(at: now)
    }

    /// Holds an install handle until the app is quiet enough to take it; internal so a test can stage one.
    func stage(_ install: @escaping () -> Void, at now: Date = Date()) {
        installNow = install
        progress = .readyToInstall
        // `refresh` rather than the check alone: the app may have told the gate nothing for hours.
        refresh(at: now)
    }

    /// Installs a staged update once the app has been quiet long enough, or schedules a wake-up.
    private func installIfTheMomentIsRight(at now: Date) {
        guard let install = installNow else { return }
        guard gate.mayInstall(at: now) else {
            scheduleWakeUp(at: now)
            return
        }
        wakeUp?.cancel()
        wakeUp = nil
        // Cleared before calling: the call ends with the app being replaced.
        installNow = nil
        // Set before the call; it is the one line the user sees before the app relaunches.
        progress = .installing
        install()
    }

    /// One sleep of exactly the time remaining, replaced whenever the remaining time changes.
    private func scheduleWakeUp(at now: Date) {
        wakeUp?.cancel()
        guard let quietDuration = gate.quietDuration(at: now) else {
            wakeUp = nil
            return
        }
        let remaining = UpdateGate.settleSeconds - quietDuration
        guard remaining > 0 else { return }
        wakeUp = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            // `refresh`, not the install check alone: the app may be busy again after a minute.
            self?.refresh()
        }
    }

    /// Settings' "Check Now"; bypasses the startup grace period and puts a window in front.
    func checkForUpdates() {
        guard Self.isConfigured else { return }
        begin(
            checksAutomatically: updater.automaticallyChecksForUpdates,
            installsAutomatically: updater.automaticallyDownloadsUpdates)
        if startupGate.mayStartManually() { controller.startUpdater() }
        // Only a check the user asked for says so; see `MenuBarPresenter.updateLine`.
        progress = .checking
        updater.checkForUpdates()
    }
}

/// A value carried across an isolation boundary; Sparkle's install handle is only called on the main actor.
private struct UncheckedSend<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) { self.value = value }
}

// MARK: - What Sparkle asks this app

extension UpdateController: SPUUpdaterDelegate {
    /// Holds Sparkle's install handle instead of waiting for a quit that never comes; Docs/app-updates.md.
    nonisolated func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        // Wrapped before it crosses to the main actor, because Sparkle's closure carries no isolation.
        let install = UncheckedSend(immediateInstallHandler)
        MainActor.assumeIsolated { stage { install.value() } }
        // True: this app decides when; false hands the decision back to a quit that never comes.
        return true
    }

    /// The feed was fetched, which is the request the Privacy pane counts as an update check.
    nonisolated func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        requestActivity.feedLoaded()
    }

    /// The feed answered and there is something to fetch.
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated { progress = .downloading(fraction: nil) }
    }

    /// The feed answered and there is nothing to fetch; back to idle, since Sparkle already says so.
    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { progress = .idle }
    }

    /// A check that failed, silently: a feed that could not be reached is not something the user can fix.
    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        requestActivity.feedFailed()
        MainActor.assumeIsolated { progress = .idle }
    }

    /// Counts the archive request before Sparkle starts it.
    nonisolated func updater(
        _ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest
    ) {
        requestActivity.archiveWillDownload()
    }

    /// Clears the feed marker so the next automatic or manual update check is counted independently.
    nonisolated func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        requestActivity.checkDidFinish()
    }

    /// Downloaded and verified; the wait for a quiet minute starts here.
    nonisolated func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated { progress = .readyToInstall }
    }

    /// Never sends anything about this Mac to the feed.
    nonisolated func feedParameters(
        for updater: SPUUpdater, sendingSystemProfile sendingProfile: Bool
    ) -> [[String: String]] {
        []
    }
}
