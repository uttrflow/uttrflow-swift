import AppKit
import Sparkle
import UttrflowUX

/// Keeping the app up to date, and the one thing this product refuses to let that cost.
///
/// Sparkle does the dangerous part — replacing a running bundle without breaking its
/// signature, its permissions or its menu-bar item — and this decides *when* it may. The
/// deciding is ``UpdateGate``, which is a tested value in `UttrflowUX`; everything here is
/// wiring, and there is deliberately no rule in it that a test cannot reach.
///
/// The second module in this app allowed to open a socket, after `UttrflowAccount`, and it
/// is written to keep that fact as checkable as the first one: one type, one feed address,
/// and it comes from the Info.plist rather than from anywhere a value could be smuggled in.
@MainActor
final class UpdateController: NSObject {
    /// Sparkle's own controller, which owns the schedule and the download.
    ///
    /// `startingUpdater: false` — the app starts it once the first launch is over. A check
    /// that fired while the speech model was still downloading would be competing with the
    /// one download the user is actually waiting for.
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    /// How the app answers "what are you doing right now?".
    ///
    /// Asked, rather than told. The app reports its activity when something changes, and
    /// the moment this type most needs an answer — a minute after the last change, when
    /// the gate is due to open — is precisely a moment when nothing has changed and
    /// nothing is reporting. An earlier version only listened, and the update sat staged
    /// for ever on an app nobody was touching, which is the exact case it exists for.
    private let activity: @MainActor () -> UpdateActivity

    private var gate = UpdateGate()

    /// Sparkle's "install it now" handle, held from the moment an update is staged until
    /// the app is quiet enough to take it.
    ///
    /// This is the whole mechanism. Sparkle's own offer is to install when the app next
    /// quits, and this app is not quit — so without holding this the update would sit
    /// there for weeks. Calling it swaps the bundle and relaunches.
    private var installNow: (() -> Void)?

    /// A wake-up for the moment the gate is due to open.
    ///
    /// Without this the update never lands. The gate opens at an instant — a minute after
    /// the app went quiet — and the app only reports its activity when something changes.
    /// An app that goes quiet and *stays* quiet reports nothing more, so the moment the
    /// gate opens is precisely a moment nothing is asking it. Found by rehearsing an
    /// update end to end and watching it sit there, staged, indefinitely.
    private var wakeUp: Task<Void, Never>?

    /// Whether the app has told Sparkle to begin. Guarded because starting twice throws.
    private var hasStarted = false

    var updater: SPUUpdater { controller.updater }

    init(activity: @escaping @MainActor () -> UpdateActivity) {
        self.activity = activity
        super.init()
    }

    /// Whether this build can update itself at all.
    ///
    /// False in a build with no feed address, which is every build made before the
    /// backend served one — and, deliberately, in every development build. A missing
    /// address is not an error to report: it is a build that was never going to update.
    ///
    /// `nonisolated` because it reads two `Info.plist` values and nothing else. The main
    /// actor was inherited from the class rather than needed, and it kept the settings
    /// screen's capability probe — which runs off the main actor — from asking the one
    /// type that knows the answer.
    nonisolated static var isConfigured: Bool {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let url = URL(string: feed), isAcceptable(url)
        else { return false }
        // A key that is not a key is worse than no key: Sparkle would have nothing to
        // check a download against, and the app would install whatever it was handed.
        // The entitlement work found the same shape of bug — an all-zero Ed25519 key
        // verified forged signatures — so the placeholder fails closed here too.
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            !key.isEmpty, !key.contains(" ")
        else { return false }
        return true
    }

    /// `https`, or `http` to this machine and nowhere else.
    ///
    /// The loopback exception is what makes the whole feature rehearsable: an update can
    /// be built, signed, served and installed on one Mac, and the thing that has to be
    /// watched happening — a running app replacing itself and keeping its permissions —
    /// can be watched. Without it that rehearsal needs a certificate for a local server,
    /// which is enough friction that it does not happen and the first real update is the
    /// first anybody has seen.
    ///
    /// It is not a hole. `127.0.0.1` is this Mac; anything that could serve an update
    /// there is already running as the user. `Scripts/bundle.sh` applies the same rule,
    /// so a build pointed at a local feed cannot be published by accident.
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

    /// Re-reads what the app is doing and acts on it.
    ///
    /// Called from the same place the main window is redrawn — every time any of the four
    /// facts could have changed — and again from the wake-up below, which is the path
    /// that matters on a Mac nobody is touching.
    func refresh(at now: Date = Date()) {
        gate.note(activity(), at: now)
        installIfTheMomentIsRight(at: now)
    }

    /// Installs a staged update the moment the app has been quiet long enough.
    ///
    /// Called from every activity report rather than from a timer: the reports arrive
    /// whenever anything changes, which is exactly when the answer can have changed, and
    /// a timer would be a second clock to keep in step with the first.
    private func installIfTheMomentIsRight(at now: Date) {
        guard let install = installNow else { return }
        guard gate.mayInstall(at: now) else {
            scheduleWakeUp(at: now)
            return
        }
        wakeUp?.cancel()
        wakeUp = nil
        // Cleared before calling, not after: the call ends with the app being replaced,
        // and a handle held across that is a handle that could be called twice.
        installNow = nil
        install()
    }

    /// Asks again when the gate is due to open, and not before.
    ///
    /// One sleep of exactly the time remaining, replaced whenever the remaining time
    /// changes, rather than a timer ticking every second for the lifetime of the app.
    /// Anything that interrupts the quiet cancels it, because the next report will start
    /// a new minute and schedule a new one.
    private func scheduleWakeUp(at now: Date) {
        wakeUp?.cancel()
        guard let quietFor = gate.quietFor(at: now) else {
            wakeUp = nil
            return
        }
        let remaining = UpdateGate.settleSeconds - quietFor
        guard remaining > 0 else { return }
        wakeUp = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            // `refresh`, not the install check alone: a minute has passed and the app may
            // well be busy now, and the gate can only learn that by asking.
            self?.refresh()
        }
    }

    /// The menu's "Check for Updates…", which is the one path that is allowed to put a
    /// window in front of somebody: they asked.
    func checkForUpdates() {
        guard Self.isConfigured else { return }
        begin(automatically: updater.automaticallyDownloadsUpdates)
        updater.checkForUpdates()
    }
}

/// A value carried across an isolation boundary, with the promise made explicit.
///
/// One use, and it is worth the four lines rather than an `@unchecked Sendable` on
/// something larger: Sparkle's installation handle is a closure it expects to be called
/// once, from anywhere, and everything this app does with it happens on the main actor.
private struct UncheckedSend<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) { self.value = value }
}

// MARK: - What Sparkle asks this app

extension UpdateController: SPUUpdaterDelegate {
    /// An update is downloaded, verified and staged, and Sparkle is about to settle for
    /// installing it the next time the app quits.
    ///
    /// Which, for a menu-bar app that is opened once and never quit, means never. So the
    /// handle it offers is kept instead, and used the moment the app has been quiet for a
    /// minute — not while somebody is dictating, reading the panel, part-way through an
    /// edit or part-way through a first run.
    ///
    /// This is the delegate call that matters, and it was found by rehearsing rather than
    /// by reading: the first version of this asked ``updaterShouldRelaunchApplication``,
    /// which is a different question — whether to *come back* after installing, not
    /// whether to install — and answering "no" there would have installed the update and
    /// left the app closed.
    nonisolated func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        // Wrapped before it crosses to the main actor. Sparkle hands over a plain
        // closure with no isolation of its own, and Swift 6 is right to object to one
        // being stored where a different actor will call it later; the wrapper says
        // plainly that the value being kept is safe to send.
        let install = UncheckedSend(immediateInstallHandler)
        MainActor.assumeIsolated {
            installNow = { install.value() }
            // `refresh` rather than the check alone: this can arrive on an app that has
            // been quiet for hours and has told the gate nothing at all.
            refresh()
        }
        // True: this app takes responsibility for when. Returning false would hand the
        // decision back to Sparkle, which would install on a quit that never comes.
        return true
    }

    /// Never send anything about this Mac to the feed.
    ///
    /// Sparkle offers to attach system profile data — OS version, model, CPU, how many
    /// times the app has been run. Uttrflow does not collect any of that anywhere else and
    /// is not going to start through the updater.
    nonisolated func feedParameters(
        for updater: SPUUpdater, sendingSystemProfile sendingProfile: Bool
    ) -> [[String: String]] {
        []
    }
}
