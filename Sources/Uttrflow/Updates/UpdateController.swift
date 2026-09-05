// Sparkle wiring, and when a staged update may install.

import AppKit
import Sparkle
import UttrflowUX

/// Decides when Sparkle may replace the running bundle; the rule is `UpdateGate`. See Docs/app-updates.md.
@MainActor
final class UpdateController: NSObject {
    /// Sparkle's own controller, started after first launch so no check competes with the model download.
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    /// Asks what the app is doing, because a quiet app reports nothing at the moment the gate opens.
    private let activity: @MainActor () -> UpdateActivity

    private var gate = UpdateGate()

    /// Sparkle's install-now handle, held from staging until the app is quiet enough to take it.
    private var installNow: (() -> Void)?

    /// Wakes the controller when the gate is due to open, since a quiet app never reports again on its own.
    private var wakeUp: Task<Void, Never>?

    /// Whether the app has told Sparkle to begin. Guarded because starting twice throws.
    private var hasStarted = false

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
            let url = URL(string: feed), isAcceptable(url)
        else { return false }
        // A placeholder key fails closed: Sparkle would install whatever the feed handed it.
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            !key.isEmpty, !key.contains(" ")
        else { return false }
        return true
    }

    /// `https`, or `http` to this machine only, so an update can be rehearsed end to end on one Mac.
    nonisolated private static func isAcceptable(_ url: URL) -> Bool {
        if url.scheme == "https" { return true }
        guard url.scheme == "http", let host = url.host else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    /// Starts checking. Called once, after the app has finished coming up.
    func begin(automatically: Bool) {
        guard Self.isConfigured, !hasStarted else { return }
        hasStarted = true
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = automatically
        controller.startUpdater()
    }

    /// The user changed the switch in Settings.
    func setInstallsAutomatically(_ isOn: Bool) {
        guard hasStarted else { return }
        updater.automaticallyDownloadsUpdates = isOn
    }

    /// Re-reads what the app is doing and acts on it; called on every redraw and from the wake-up.
    func refresh(at now: Date = Date()) {
        gate.note(activity(), at: now)
        installIfTheMomentIsRight(at: now)
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

    /// The menu's "Check for Updates…", the one path allowed to put a window in front of somebody.
    func checkForUpdates() {
        guard Self.isConfigured else { return }
        begin(automatically: updater.automaticallyDownloadsUpdates)
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
        MainActor.assumeIsolated {
            installNow = { install.value() }
            progress = .readyToInstall
            // `refresh` rather than the check alone: the app may have told the gate nothing for hours.
            refresh()
        }
        // True: this app decides when; false hands the decision back to a quit that never comes.
        return true
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
        MainActor.assumeIsolated { progress = .idle }
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
