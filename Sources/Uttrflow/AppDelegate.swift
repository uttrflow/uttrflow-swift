import AppKit
import OSLog
import UttrflowAI
import UttrflowAccount
import UttrflowAudio
import UttrflowClipboard
import UttrflowContext
import UttrflowCore
import UttrflowDictionary
import UttrflowHistory
import UttrflowInput
import UttrflowPermissions
import UttrflowPipeline
import UttrflowSettings
import UttrflowSpeech
import UttrflowUX

/// Assembles the product and keeps it running.
///
/// The only place that names concrete engines. It builds them once, hands them to the
/// pipeline, and then does nothing but relay: state out to the interface, gestures back
/// in. Everything it relays was decided somewhere testable.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// Records what actually happened to each dictation.
    ///
    /// The three ways insertion can go wrong are indistinguishable from outside the app:
    /// the words can be written straight in, pasted, or left on the clipboard, and a
    /// failure of the first two looks exactly like a failure of the third. Reading this
    /// back with `log show --predicate 'subsystem == "com.uttrflow.Uttrflow"' --last 5m`
    /// turns "it just does not insert" into a specific question.
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "insertion")

    private let settingsStore: any SettingsStore = UserDefaultsSettingsStore()
    private var settings = Settings()

    private let menuBar = MenuBarController()
    private let dock = DockPanelController()
    private var recents = RecentDictations()
    /// Where dictations are kept between launches.
    ///
    /// `recents` is the menu bar's synchronous view of this — the menu is drawn on the
    /// main actor and cannot await an actor — and is replaced from the store on the next
    /// refresh, so the store remains the only thing that decides what has been deleted.
    private let history: DictationHistoryStore
    /// The words this user says that a general model would not expect.
    ///
    /// Reached by three parts of one dictation — the recogniser is conditioned with it
    /// before decoding, the correction engine consults it after, and whatever it got
    /// right is counted back into it — so there is exactly one of these and all three
    /// share it. Two stores over one file would be two caches disagreeing about what is
    /// in it.
    private let dictionary: PersonalDictionaryStore
    private let snippets: SnippetStore
    /// The backend and the cache that believes what it signs, made **once**.
    ///
    /// Shared with onboarding rather than defaulted twice.
    /// ``InMemoryAuthenticationService`` mints a fresh Ed25519 key per instance, so a
    /// second layer would produce a profile cache that rejects every entitlement the
    /// first one signed — the user would sign in through onboarding and find the Account
    /// page still showing them signed out, with a signature error nobody could act on.
    private let account = OnboardingAccountLayer.forThisBuild()
    /// Whether a renewal could even be attempted.
    ///
    /// Only ever changes what the Account page *says* about an aged-out entitlement —
    /// ``EntitlementGate`` permits the dictation either way. Passing a hardcoded `true`
    /// here would tell somebody on a plane to sign in again, which they cannot do.
    private let network: any NetworkReachability = SystemNetworkReachability()
    /// What macOS is told about starting Uttrflow at login.
    ///
    /// Held rather than made where it is used, so a test can stand in for the system and
    /// check the switch reaches it. The switch was read by nothing at all until now, and
    /// no test could have said so.
    private let loginItem: LaunchAtLogin
    /// Read for the vocabulary before decoding and for the tidier afterwards. Shared so
    /// the second reading of a dictation is the cheap warm one.
    private let context = MacContextEngine()
    /// Held rather than made where it is used, because the menu has to say whether the
    /// speech model is ready every time it is drawn, not only when the pipeline is built.
    private let modelStore = FileSystemSpeechModelStore.whisperKit()

    /// Keeps the per-stage timings the pipeline already measures.
    ///
    /// Without this the pipeline measured every stage and handed the numbers to
    /// ``NoOpMetricsRecorder``, which throws them away — so the diagnostics page had
    /// nothing to report and never could have. It is held here because it must outlive
    /// any one dictation: the page reports on the session, not the last utterance.
    private let diagnostics = DiagnosticsRecorder()

    private var pipeline: DictationPipeline?
    private var controller: DictationController<ContinuousClock>?
    private var stateTask: Task<Void, Never>?
    private var dismissalTask: Task<Void, Never>?

    // MARK: The clipboard

    private let clipboard: ClipboardStore

    /// Builds the app around one folder.
    ///
    /// The folder is an argument so that the intents a page reports can be driven
    /// against a temporary one in a test. Without it every store defaulted separately to
    /// the real Application Support folder, which made ``carryOut(_:)`` — the switch
    /// every button in the product goes through — impossible to exercise without
    /// rewriting the user's own dictionary.
    ///
    /// - Parameters:
    ///   - container: Where the four stores keep their files.
    ///   - loginItem: What to tell about starting at login. Substituted in tests so that
    ///     running the suite does not add a login item to the machine running it.
    init(container: URL = .applicationSupportDirectory, loginItem: LaunchAtLogin = LaunchAtLogin()) {
        self.loginItem = loginItem
        history = DictationHistoryStore(file: DictationHistoryStore.defaultFile(in: container))
        dictionary = PersonalDictionaryStore(
            file: PersonalDictionaryStore.defaultFile(in: container))
        snippets = SnippetStore(file: SnippetStore.defaultFile(in: container))
        clipboard = ClipboardStore(file: ClipboardStore.defaultFile(in: container))
        super.init()
    }
    private let clipboardWatcher = PasteboardWatcher(source: SystemClipboardSource())
    private let quickPanel = QuickPanelController()

    /// Keeping the app up to date. Inert in a build with no feed address, which is every
    /// build made before one is configured — see ``UpdateController/isConfigured``.
    ///
    /// It asks this delegate what the app is doing rather than being told, because the
    /// moment it needs to know is a moment when nothing is happening.
    private lazy var updates = UpdateController { [weak self] in
        // No delegate means no idea, and no idea means do not interrupt.
        self?.updateActivity ?? UpdateActivity(isDictating: true)
    }
    /// A monitor of its own rather than the dictation controller's.
    ///
    /// Carbon keys a registration on an identifier it hands out per registration, so two
    /// monitors coexist without either knowing about the other. Sharing one would mean
    /// one binding, and this shortcut and the dictation shortcut are not the same key.
    private let clipboardHotkeys = CarbonHotkeyMonitor()
    /// Asked, when the panel opens, whether a paste can be placed rather than merely
    /// copied. Held rather than made each time so the answer costs one call.
    private let accessibility = AccessibilityPermissionGate()
    private let microphone = MicrophonePermissionGate()
    private let focus: any AccessibilityFocus = AXAccessibilityFocus()
    /// D5 — asked, when the panel opens, which languages have a formatter on this disk.
    private let formatter: any CodeFormatting = SystemCodeFormatter()

    /// The clipboard, with the watcher told before every write Uttrflow makes.
    ///
    /// One pasteboard shared by everything that inserts text, rather than one built at
    /// each call site, because the call sites diverged and nothing noticed. The clip
    /// path was given the announcement and the dictation path was left on
    /// a bare `SystemPasteboard`, whose `willWrite` is empty by default — so a dictation that
    /// fell back to a paste was recorded twice: once as itself, and once by the watcher
    /// as a copy from whichever application was in front.
    ///
    /// The default is the trap. It is there so that callers who never write are
    /// unaffected, which is right, and it means an inserter that forgets this is not a
    /// compile error but a silent second row. Naming the thing after the guarantee, and
    /// having exactly one of it, is what makes the next inserter get it by default.
    private lazy var announcingPasteboard = SystemPasteboard {
        [clipboardWatcher] in clipboardWatcher.ignoreNextWrite(of: $0)
    }

    /// Puts a chosen clip where the caret is.
    ///
    /// The paste leaves the clip on the clipboard, deliberately and permanently — the
    /// paste engine explains why — so without the announcement it reads as the user
    /// copying it, and the clip climbs to the top of the panel every time it is used.
    private lazy var clipInserter = TextInsertion.coordinator(
        pasteboard: announcingPasteboard)

    /// The panel's state while it is open, and `nil` for "not open".
    ///
    /// Held here because the panel is a window and windows have no memory: every key it
    /// reports is answered against this and the answer put back.
    private var panel: PanelSnapshot?
    private var clipboardWatchTask: Task<Void, Never>?
    private var clipboardHotkeyTask: Task<Void, Never>?

    /// F7, F9 — the clip a delete just removed, for as long as it can be undone.
    ///
    /// Held by the app rather than by the panel because the undo has to outlive the
    /// panel, which is dismissed constantly and by design. The store has forgotten the
    /// clip by the time the delete returns, so this is the only way back to it.
    private var undoable: Clip?
    private var undoTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    /// A3, A7 — where the user was when the panel last closed, for as long as reopening
    /// counts as undoing an accident rather than starting again.
    private var resume: PanelResume?
    /// Long enough to notice the row vanish and reach for the keyboard; short enough that
    /// an undo never applies to a delete the user has stopped thinking about.
    private static let undoWindow = Duration.seconds(8)

    /// Internal so `UttrflowTests` can install one without showing it.
    ///
    /// `MainWindowController` builds no `NSWindow` until `show(_:)`, so a test can hold
    /// one, drive an intent and read back what the editor is holding — which is the only
    /// way to check that opening an editor opened it on the right row. Without it that
    /// test could only assert what it had itself passed in.
    var mainWindow: MainWindowController?
    /// The settings window, over the app's own stores.
    ///
    /// `personalisation` is passed rather than left to default, which the default's own
    /// documentation asks for: it builds a fresh `PersonalDictionaryStore` and
    /// `DictationHistoryStore` at the standard paths, and those would be second actors
    /// over the files this app already holds — two writers racing for one file, and two
    /// caches disagreeing about what is in it. It also means the four resets now act on
    /// the same stores every page is drawn from.
    ///
    /// `onReset` is what makes a reset visible. Forgetting every word is carried out by
    /// the settings window; without this the main window would go on listing the words
    /// until something else happened to redraw it.
    private lazy var settingsWindow = SettingsWindowController(
        store: settingsStore,
        personalisation: FilePersonalisationStore(
            dictionary: dictionary, history: history, clipboard: clipboard),
        onChange: { [weak self] settings in self?.settingsChanged(to: settings) },
        onReset: { [weak self] _ in self?.refreshMainWindow() },
        onShortcutRecording: { [weak self] isRecording in
            self?.shortcutRecordingChanged(to: isRecording)
        })
    private var onboarding: OnboardingWindowController?
    /// What the user has typed into each page's search field, and which scope each page
    /// has selected.
    ///
    /// Kept here because the window is rebuilt from a fresh snapshot on every change and
    /// would otherwise forget the query mid-search — and kept **per page** because there
    /// is a search field on six of them. One shared string meant searching History for
    /// "invoice" and then clicking Dictionary, which arrived prefilled and reported "No
    /// word in your dictionary looks or sounds like 'invoice'".
    private var queries: [MainTab: String] = [:]
    private var scopes: [MainTab: String] = [:]

    /// How long a finished result stays on screen before the button shrinks back.
    ///
    /// Without this the last thing dictated sits legibly on top of every application
    /// for ever, and the panel keeps swallowing clicks in that corner of the screen.
    private static let successLingers = Duration.seconds(2)
    /// A failure stays longer, because it is asking the user to do something — but it
    /// still goes, so a single bad dictation cannot leave the app permanently unusable.
    private static let failureLingers = Duration.seconds(10)

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = settingsStore.load()
        // Reconciled at launch as well as on change: the user can remove the login item
        // in System Settings without telling the app, and a preference that says "on"
        // over a system that says "off" is a switch lying about what will happen.
        applyAppearance()
        applyLaunchAtLogin()
        buildPipeline()
        wireInterface()
        startWatchingForTheShortcut()
        startWatchingTheClipboard()
        Task { await pipeline?.prepare() }
        refreshAccount()
        presentOnboardingIfNeeded()
        // Shown at launch, because an interface reachable only through a menu-bar icon is
        // an interface most people never find. Not while onboarding is up: two windows
        // competing on a first run is two things to dismiss before anything works.
        if onboarding == nil { show(.main(.home)) }
        // Last, and only once the rest of the launch is done: a check that fired while
        // the speech model was still downloading would be competing with the one
        // download the user is actually waiting for.
        // From the setting, not hardcoded. It was `true` here, which meant the switch in
        // Settings governed the running process and was then forgotten at every launch —
        // a setting that appears to work and silently reverts, which is worse than one
        // that plainly does nothing.
        // Redraw when it changes. Without this the line would only appear the next time
        // something *else* redrew the menu bar — which, on an idle Mac waiting out its
        // quiet minute, is nothing at all.
        updates.onProgressChanged = { [weak self] in
            guard let self else { return }
            menuBar.update(with: MenuBarPresenter.present(menuBarState(for: lastDictationState)))
        }
        updates.begin(automatically: settings.installsUpdatesAutomatically)
    }

    /// Re-reads the account from the server, in the background, at every launch.
    ///
    /// The server owns the truth about who this is and what they have paid for; this Mac
    /// holds a copy, and a copy that is never re-read is a copy that is eventually wrong —
    /// a subscription bought on the website, a plan cancelled, a name changed on a phone.
    /// The call is cheap by design: the backend answers `304` when nothing has changed.
    ///
    /// Nothing waits for it and nothing fails because of it. A Mac with no network keeps
    /// the profile it has and starts exactly as fast, which is the whole reason the copy
    /// exists.
    private func refreshAccount() {
        Task { [account] in
            let outcome = await account.refresh.run()
            // Only a change is worth a redraw. `unchanged` is the common answer and
            // repainting on it would be a launch that flickers for nothing.
            guard outcome == .updated || outcome == .signedOut else { return }
            refreshMainWindow()
        }
    }

    /// Clicking the Dock icon of an app with no visible window.
    ///
    /// Without this, closing the window leaves the Dock icon doing nothing — which is the
    /// one thing every Mac user expects a Dock icon to do.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows: Bool
    ) -> Bool {
        if !hasVisibleWindows { show(.main(.home)) }
        return true
    }

    // MARK: The menu bar at the top of the screen

    @objc func showMainWindowFromMenu(_ sender: Any?) { show(.main(.home)) }
    @objc func showSettingsFromMenu(_ sender: Any?) { show(.settings(.general)) }
    @objc func showDiagnosticsFromMenu(_ sender: Any?) { show(.main(.diagnostics)) }

    /// Shows or hides the sidebar's names.
    ///
    /// Does nothing when no window has been built yet, which is the honest answer: there
    /// is no sidebar to widen, and building a window to widen it would be a menu item
    /// that opens a window without saying so.
    @objc func toggleSidebarFromMenu(_ sender: Any?) { mainWindow?.toggleSidebar() }

    /// Names the sidebar item after what choosing it will do, the way macOS does.
    ///
    /// A fixed "Show Sidebar" would be wrong half the time, and wrong in the direction
    /// that matters: somebody reading it while the sidebar is open is being told the
    /// opposite of what will happen.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(toggleSidebarFromMenu(_:)) else { return true }
        item.title = mainWindow?.isSidebarExpanded == true ? "Hide Sidebar" : "Show Sidebar"
        return mainWindow != nil
    }

    /// Shows the first-run flow, and only on a first run.
    ///
    /// The rest of the app is assembled first and deliberately not gated behind this:
    /// someone who quits halfway through onboarding still has a working menu bar, and
    /// the flow itself skips whatever is already granted rather than asking twice.
    private func presentOnboardingIfNeeded() {
        guard OnboardingWindowController(settingsStore: settingsStore, account: account).isRequired
        else { return }
        presentOnboarding(skippingWelcome: false)
    }

    /// Builds the flow and puts it on screen.
    ///
    /// Also what the Account page's Sign In reaches, with the pitch skipped. The window
    /// is rebuilt each time rather than kept, because a flow that has already finished
    /// holds its last page and would open showing it.
    private func presentOnboarding(skippingWelcome: Bool, askingToSignIn: Bool = false) {
        let onboarding = OnboardingWindowController(settingsStore: settingsStore, account: account)
        self.onboarding = onboarding
        onboarding.onFinish = { [weak self] _ in
            guard let self else { return }
            // Re-read rather than patched: the microphone check can preset the language
            // list while the flow is open, and it writes through the same store.
            settingsChanged(to: settingsStore.load())
            self.onboarding = nil
            // The session is the one thing onboarding changes that the main window shows
            // and the settings store knows nothing about.
            refreshMainWindow()
        }
        // Fires however the window goes, including the red button. Signing in and then
        // shutting the window is an ordinary thing to do, and it changes what the Account
        // page should say.
        onboarding.onClose = { [weak self] in self?.refreshMainWindow() }
        onboarding.present(skippingWelcome: skippingWelcome, askingToSignIn: askingToSignIn)
    }

    /// Finishes the dictation in flight before letting the process die.
    ///
    /// Quitting mid-dictation used to take the audio, the transcript and the cleaned
    /// text with it, silently. Nothing is written to disk yet, so the only way not to
    /// lose the words is not to exit until they have somewhere to go.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let pipeline else { return .terminateNow }

        Task { [weak self] in
            if await pipeline.currentState.isBusy {
                for await state in await pipeline.states() where !state.isBusy {
                    break
                }
            }
            await self?.controller?.stop()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        stateTask?.cancel()
        dismissalTask?.cancel()
    }

    // MARK: Assembly

    private func buildPipeline() {
        let model = SpeechModel.default

        let speech = SpeechEngineFactory.make(
            kind: settings.engines.speech, model: model,
            modelFolder: modelStore.location(of: model),
            vocabulary: DictionaryVocabulary { [dictionary, context] in
                // One reading, so the words are ranked against the screen they were
                // ranked for. Asked once a dictation, after the microphone has closed
                // and before the decoder starts, which is where the recogniser asks.
                await (dictionary.allEntries(), context.currentContext(), Date())
            })

        // Held rather than left inside the capture engine so the floating button can
        // read the level without going through an actor: the accumulator is a
        // lock-guarded `Sendable` box, and a meter polling it twenty times a second
        // should not have to queue behind a `stop()` busy converting a recording.
        let microphone = AVAudioCaptureEngine(
            source: AVAudioEngineMicrophoneSource())
        dock.setLevelSource { microphone.momentaryLevel }

        let pipeline = DictationPipeline(
            capture: microphone,
            speech: speech,
            cleaner: TextTransformers.router(configuration: settings.engines),
            context: context,
            // Announced, like every other write this app makes — and this is the call
            // site that was not.
            //
            // A dictation that falls back to a paste writes the words to the clipboard,
            // and unannounced that write is a copy: the watcher's next tick recorded the
            // dictation a second time, under whichever application was in front. The
            // store merged the two by text and took the arrival's `source`, which is the
            // watcher's — so `recordAsClip` wrote "Dictation", it was overwritten within
            // 200ms, and not one dictation on this disk carries the word. Every reader of
            // that string was reading something that never survived.
            //
            // It also stopped the two lists working at all. Once repeats merge only
            // within one origin the two records no longer collapse, so every dictation
            // wrote one row into From Uttrflow and an identical one to the top of
            // History — the burying the split exists to prevent, doubled.
            inserter: TextInsertion.coordinator(pasteboard: announcingPasteboard),
            corrector: DictionaryCorrections(dictionary: dictionary),
            snippets: StoredSnippets(store: snippets),
            learner: StoreCounters(dictionary: dictionary, snippets: snippets),
            vocabulary: LearnedVocabulary(dictionary: dictionary),
            metrics: diagnostics,
            profile: settings.profile
        )
        self.pipeline = pipeline

        controller = DictationController(
            pipeline: pipeline,
            monitor: ActivationMonitor(),
            cue: settings.playsSoundWhenRecordingStarts
                ? SoundPlayingRecordingCue(player: SystemSoundPlayer()) : SilentCue(),
            activation: settings.hotkeyActivation,
            clock: ContinuousClock()
        )
    }

    private func wireInterface() {
        guard let pipeline else { return }

        menuBar.onCommand = { [weak self] intent in self?.carryOut(intent) }

        // Pressing and holding the floating button does exactly what holding the
        // shortcut does, so neither path is a second implementation of the other.
        // Submitted rather than handled directly: the controller queues every gesture
        // behind one consumer, so a press and a release cannot interleave.
        dock.onPressBegan = { [weak self] in self?.controller?.submit(.pressed) }
        dock.onPressEnded = { [weak self] in self?.controller?.submit(.released) }
        dock.onRecoveryAction = { [weak self] action in self?.perform(action) }

        dock.setShortcut(SettingsShortcut.compact(settings.hotkey))
        dock.setShrinksToGrip(settings.shrinksToGripWhenIdle)
        if settings.showsFloatingButton {
            dock.setAnchor(settings.floatingButtonAnchor)
            dock.show()
        }

        stateTask = Task { [weak self] in
            for await state in await pipeline.states() {
                self?.render(state)
            }
        }
    }

    /// Stands the live shortcut down while the user is choosing a new one, and brings it
    /// back afterwards.
    ///
    /// A key press typed at the shortcut field is swallowed by that field's own monitor,
    /// so it never reached the app. A held modifier cannot be: the field passes flag
    /// changes on deliberately, because swallowing them would leave the rest of the app
    /// believing a key is still down. So with Fn bound, pressing Fn to record it also
    /// started a real dictation behind the settings window — one nothing in that window
    /// could then stop.
    private func shortcutRecordingChanged(to isRecording: Bool) {
        if isRecording {
            Task { [weak self] in await self?.controller?.stop() }
        } else {
            startWatchingForTheShortcut()
        }
    }

    private func startWatchingForTheShortcut() {
        guard let controller else { return }
        let binding = settings.hotkey
        Task { [weak self] in
            do throws(HotkeyError) {
                try await controller.start(binding: binding)
            } catch {
                // Carbon needs no permission, so this should not happen — but a
                // shortcut already claimed by another app can refuse. Say so rather
                // than leaving the user with a key that does nothing.
                //
                // The catch used to name `ClipboardStoreError`, which `start` cannot
                // throw — so the clause matched nothing, the `Task` swallowed the real
                // `HotkeyError`, and a shortcut that failed to register did exactly what
                // this comment says it must not: nothing, silently.
                self?.render(.failed(DictationFailure(error)))
            }
        }
    }

    // MARK: The clipboard

    /// How long unkept clips live, measured from now.
    ///
    /// Read on every use rather than held, because both halves move: the window is a
    /// setting the user can change while the app runs, and `now` is the whole point.
    private var retention: ClipRetention {
        ClipRetention(
            days: settings.clipboardRetentionDays, now: Date(),
            // One control, both copies. The Privacy pane offers a single window and it
            // said "transcripts"; the clipboard's copy of the same transcript aged by a
            // setting with no screen at all.
            dictationDays: settings.transcriptRetentionDays)
    }

    private func startWatchingTheClipboard() {
        quickPanel.onKey = { [weak self] key, behind in
            self?.panelAnswered(key, behind: behind)
        }
        quickPanel.onIntent = { [weak self] intent in self?.carryOut(intent) }

        // Built here rather than inside the `Task`, because a `[weak self]` closure
        // nested inside another closure captures the outer closure's binding rather than
        // making one of its own, which Swift 6 refuses outright.
        let arrived: @Sendable (NoticedClip) async -> Void = { [weak self] noticed in
            await self?.clipArrived(noticed)
        }
        clipboardWatchTask = Task { [clipboardWatcher] in
            await clipboardWatcher.run(handing: arrived)
        }

        startWatchingForTheClipboardShortcut()
    }

    /// Keeps a clip the user has just copied, and shows it if they are looking.
    private func clipArrived(_ noticed: NoticedClip) async {
        // Best-effort on purpose. A disk that refuses the write loses one clip; giving up
        // on watching would lose every clip after it, and the user can do nothing about
        // either.
        _ = try? await clipboard.record(noticed, keeping: retention)
        await refreshPanelIfOpen()
    }

    /// A second registration, for a second key.
    ///
    /// Silent when the user has no clipboard shortcut: that is a position they are
    /// allowed to hold, not a failure, and the panel is still reachable from the menu
    /// bar. A refusal is logged rather than pushed through the dictation state machine —
    /// it says nothing about dictation, and putting it on the floating button would
    /// report a broken microphone to somebody whose microphone is fine.
    private func startWatchingForTheClipboardShortcut() {
        guard let binding = settings.clipboardHotkey else { return }
        do {
            try clipboardHotkeys.start(binding: binding)
        } catch {
            Self.log.error("clipboard shortcut refused: \(error.userMessage, privacy: .public)")
            return
        }
        clipboardHotkeyTask = Task { [weak self, clipboardHotkeys] in
            for await event in clipboardHotkeys.events {
                // Releases are ignored: this key opens a window, and a window that shut
                // itself when the key came up would be unusable by anyone who holds a
                // shortcut a fraction of a second too long.
                guard event == .pressed else { continue }
                await self?.toggleQuickPanel()
            }
        }
    }

    /// The shortcut is a toggle, so the same key puts the panel away again.
    private func toggleQuickPanel() async {
        guard !quickPanel.isVisible else {
            closeQuickPanel()
            return
        }
        let clips = await clipboard.clips(keeping: retention)
        let placement = await placement()
        // Built fresh every time, which is what makes a revealed secret unable to outlive
        // the panel it was revealed in — and what clears the last notice.
        var snapshot = PanelSnapshot.opening(
            clips: clips, now: Date(), insertion: placement, resuming: resume)
        snapshot.dictation = await voice()
        // K4, B8 — where the pictures are, and which of them are no longer there. Asked
        // once on the way in rather than while drawing: whether a file exists is a fact
        // about this moment, and a presenter that asked it would answer differently every
        // time it was called with the same input.
        snapshot.imagesFolder = await clipboard.imagesFolder
        snapshot.missingImages = await missingPictures(among: clips)
        snapshot.formattableLanguages = await formattable(among: clips)
        // A4 — said on the way in rather than after Return, so somebody who has not
        // granted Accessibility learns it while looking at the panel instead of by
        // pressing a key and watching nothing happen.
        if case .clipboardOnly(let obstacle) = placement, obstacle == .accessibilityNotGranted {
            snapshot.notice = obstacle.notice
        }
        panel = snapshot
        quickPanel.show(PanelPresenter.present(snapshot))
    }

    /// B3–B5 — whether Return will place a clip at the caret, or only copy it.
    ///
    /// Asked when the panel opens rather than after Return, because once the panel has
    /// closed there is nowhere left to say that the words only reached the clipboard. Both
    /// obstacles are knowable in advance, so the user finds out on the screen they are
    /// already looking at instead of by noticing nothing happened.
    ///
    /// The focus question is asked of the application behind the panel, which is the one
    /// the text is going into.
    private func placement() async -> PanelInsertion {
        // The rule itself is `PanelInsertion.decided`, where a test can reach it. What is
        // left here is the two questions only the machine can answer.
        //
        // It no longer asks whether anything is focused. That was the old engine
        // precondition, removed from the paste path once already after it refused every
        // application that path exists to serve, and it had survived here — so the panel
        // announced "Copied — press ⌘V" for editors that would have taken the paste
        // without complaint, and never called the engine that would have done it.
        await PanelInsertion.decided(
            isAccessibilityGranted: accessibility.status() == .granted,
            isSelfFrontmost: focus.isSelfFrontmost())
    }

    /// D5 — which of the languages actually present in the list have a formatter.
    ///
    /// Asked per language rather than per clip, and only for languages that turned up:
    /// a list of four hundred text clips asks nothing at all.
    private func formattable(among clips: [Clip]) async -> Set<CodeLanguage> {
        var answered: Set<CodeLanguage> = []
        for language in Set(clips.compactMap(\.language)) {
            if await formatter.isAvailable(for: language) { answered.insert(language) }
        }
        return answered
    }

    /// B8 — the picture clips whose files are gone.
    ///
    /// One `stat` per picture clip and none at all for the text ones, which is nearly all
    /// of them. Worth paying on the way in: the alternative is a row that draws a blank
    /// where a thumbnail should be and a Return that pastes nothing.
    private func missingPictures(among clips: [Clip]) async -> Set<Clip.ID> {
        var missing: Set<Clip.ID> = []
        for clip in clips {
            guard let image = clip.image else { continue }
            if await clipboard.imageData(for: image) == nil { missing.insert(clip.id) }
        }
        return missing
    }

    /// I6, I7 — whether the microphone can start a dictation, and why not when it cannot.
    ///
    /// Both are asked when the panel opens, so a dimmed button always carries its reason.
    /// A microphone that is off and says nothing is one the user presses twice and then
    /// stops trusting.
    private func voice() async -> PanelDictation {
        guard await microphone.status() == .granted else {
            return .unavailable(.microphoneNotGranted)
        }
        guard modelStore.isInstalled(.default) else {
            return .unavailable(.modelNotReady(percent: nil))
        }
        return .ready
    }

    /// Answers one keystroke the panel has reported, and does what the answer says.
    ///
    /// The decision is not taken here — ``PanelSnapshot/applying(_:)`` decides what the
    /// key means and ``PanelOutcome/effect`` decides what to do about it, both under
    /// test. This file is excluded from the coverage gate, so it relays and nothing more.
    /// A8 — the application the panel opened over has quit while it was up.
    ///
    /// Asked here rather than at the moment of the paste, because by then the panel has
    /// closed and there is nowhere left to say anything. The answer is folded into the
    /// snapshot so the ordinary ``PanelOutcome/copyOnly(_:_:)`` path reports it: the words
    /// go to the clipboard and the panel says where they went, which is what the
    /// specification asks for instead of failing at the moment of paste.
    ///
    /// It is a fact about the machine and so cannot live in the model, but the *decision*
    /// still does — this only supplies a fresher answer to the question the model already
    /// asks.
    private func panelAnswered(_ key: PanelKey, behind: NSRunningApplication?) {
        if let behind, behind.isTerminated, panel?.insertion == .atCaret {
            panel?.insertion = .clipboardOnly(.nothingFocused)
        }
        panelAnswered(key)
    }

    private func panelAnswered(_ key: PanelKey) {
        guard let snapshot = panel else { return }
        let response = snapshot.applying(key)
        panel = response.state

        switch response.outcome.effect {
        case .redraw:
            quickPanel.update(PanelPresenter.present(response.state))
        case .close:
            closeQuickPanel()
        case .closeAndInsertImage(let clip):
            closeQuickPanel()
            insertImage(clip)
        case .say(let notice):
            // Stays open: the row this is about is behind the notice, and taking it away
            // would leave the user with a sentence about a clip they can no longer see.
            panel?.notice = notice
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            closeAfterReading()
        case .closeAndInsertFormatted(let text, let richText, let used):
            closeQuickPanel()
            insert(text, richText: richText, used: used)
        case .closeAndInsert(let text, let used):
            // Closed first, and not afterwards. The panel is over the application the
            // text is going into, and the insertion path declines outright while
            // Uttrflow is the front application.
            closeQuickPanel()
            insert(text, used: used)
        case .copyAndSay(let text, let notice, let used):
            // Stays open, deliberately. The panel is the only surface left that the user
            // is looking at, and the sentence is the whole point of this outcome.
            putOnClipboard(text, used: used)
            panel?.notice = notice
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            closeAfterReading()
        case .applyAndRedraw(let change):
            quickPanel.update(PanelPresenter.present(response.state))
            apply(change)
        }
    }

    /// Carries out a change in the store and draws the result.
    ///
    /// The panel is redrawn from what the store hands back rather than from the change
    /// that was asked for, so a write the disk refused shows the clip as it still is
    /// instead of as the user hoped.
    private func apply(_ change: PanelChange) {
        Task {
            do {
                try await carryOut(change)
            } catch let failure as ClipboardStoreError {
                // F10 — the panel stays open holding the failure. A write that did not
                // happen has to look different from one that did, and this is the only
                // surface the user is still looking at.
                Self.log.error(
                    "clipboard write refused: \(failure.userMessage, privacy: .public)")
                panel?.notice = .writeFailed(failure.userMessage)
            }
            await refreshPanelIfOpen()
        }
    }

    /// The write itself, with every refusal allowed to reach the caller.
    private func carryOut(_ change: PanelChange) async throws(ClipboardStoreError) {
        switch change {
        case .setAlias(let id, let alias):
            _ = try await clipboard.setAlias(alias, of: id, keeping: retention)
        case .setCategory(let id, let category):
            _ = try await clipboard.setCategory(category, of: id, keeping: retention)
        case .delete(let id):
            // F7, F9 — kept in hand for the length of the undo window, because the
            // store has forgotten it the moment this returns and the clip is the only
            // way back. Held here rather than in the panel: the undo has to survive
            // the panel closing, which it does constantly and by design.
            undoable = panel?.clips.first { $0.id == id }
            panel?.canUndoDelete = undoable != nil
            Self.log.info(
                "delete: undoable=\(self.undoable != nil, privacy: .public) flag=\(self.panel?.canUndoDelete == true, privacy: .public)"
            )
            _ = try await clipboard.delete(id, keeping: retention)
            await startForgettingTheUndo()
        case .create(let text):
            // Kind detected here rather than trusted from the panel: the panel knows
            // what was typed, and what a string *is* is the store's question.
            let kind = ClipKindDetector.kind(of: text)
            let clip = Clip(
                text: text, kind: kind, copiedAt: Date(), source: nil,
                // Uttrflow made this one too — it was typed into the panel's search field
                // and kept, never copied from anywhere — so it belongs with the rest of
                // what the app produced rather than among things that came off a ⌘C.
                origin: .uttrflow,
                language: kind == .code ? CodeLanguage.detect(text) : nil)
            _ = try await clipboard.record(clip, keeping: retention)
        case .rewriteText(let id, let tidied):
            _ = try await clipboard.setText(tidied, of: id, keeping: retention)
        case .setRichText(let id, let note):
            _ = try await clipboard.setRichText(note, of: id, keeping: retention)
        case .renameCategory(let from, let to):
            // Every clip filed under the old name, moved. No alias is touched, which
            // is what the sheet promises: a collection is a shelf, not part of a
            // clip's identity.
            for clip in await clipboard.clips(keeping: retention) where clip.category == from {
                _ = try await clipboard.setCategory(to, of: clip.id, keeping: retention)
            }
        case .deleteCategory(let name, let destination):
            for clip in await clipboard.clips(keeping: retention) where clip.category == name {
                _ = try await clipboard.setCategory(
                    destination, of: clip.id, keeping: retention)
            }
        case .deleteCategoryAndClips(let name):
            for clip in await clipboard.clips(keeping: retention) where clip.category == name {
                _ = try await clipboard.delete(clip.id, keeping: retention)
            }
        case .restore(let clip):
            _ = try await clipboard.record(clip, keeping: retention)
            undoable = nil
            panel?.canUndoDelete = false
        }
    }

    /// The undo offer expires, so that a delete from ten minutes ago cannot be reversed
    /// by a keystroke aimed at something else entirely.
    private func startForgettingTheUndo() async {
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: AppDelegate.undoWindow)
            guard !Task.isCancelled else { return }
            self?.undoable = nil
            self?.panel?.canUndoDelete = false
            await self?.refreshPanelIfOpen()
        }
    }

    /// The row's own buttons, for the ones the panel cannot answer alone.
    private func carryOut(_ intent: PanelIntent) {
        // Insert and reveal are keystrokes wearing a button, and go the one path Return
        // goes, so a click and a key can never come to mean different clips.
        if let key = intent.key {
            panelAnswered(key)
            return
        }

        switch intent {
        case .pin(let id): setPinned(true, of: id)
        case .unpin(let id): setPinned(false, of: id)
        case .copy(let id):
            // Onto the clipboard and no further: the user means to paste it themselves,
            // somewhere this panel cannot reach.
            guard let clip = panel?.clips.first(where: { $0.id == id }) else { return }
            putOnClipboard(clip.text, richText: clip.richText, used: clip.id)
            closeQuickPanel()
        case .keepQuery(let text):
            apply(.create(text))
        case .dictate:
            // Closed first, then the ordinary dictation. The words go to the caret by the
            // one insertion path that is known to work, and the dock reports the progress
            // — a second live transcript in a panel that has to close before it can finish
            // would be two places describing one dictation.
            closeQuickPanel()
            Task { [weak self] in await self?.controller?.toggleFromControl() }
        case .openAccessibilitySettings:
            closeQuickPanel()
            Task { await openSettingsPane(.accessibility) }
        case .undoDelete:
            Self.log.info("undo requested: have=\(self.undoable != nil, privacy: .public)")
            guard let clip = undoable else { return }
            undoTask?.cancel()
            apply(.restore(clip))
        case .format(let id):
            runFormatter(on: id)
        case .openSettings:
            // Closed first. Settings is a real window and activates the app, and a panel
            // still on screen over it would be a floating strip belonging to nothing.
            closeQuickPanel()
            show(.settings(.general))
        case .insert, .reveal, .alias, .move, .delete, .renameCategory, .deleteCategory,
            .reindent, .makeNote, .tickBox, .scope:
            // Answered above, by `intent.key`.
            break
        }
    }

    private func setPinned(_ isPinned: Bool, of id: UUID) {
        Task { [clipboard] in
            _ = try? await clipboard.setPinned(isPinned, of: id, keeping: retention)
            await refreshPanelIfOpen()
        }
    }

    /// D5, D6, D7 — runs the installed formatter and offers what it produced.
    ///
    /// The guard is applied here, before the user is shown anything, so a formatter that
    /// dropped a line never gets as far as a diff somebody might accept. D7's quiet
    /// failure covers both: a formatter that refused and one whose output was not
    /// faithful are the same thing to the user — the clip is unchanged, and nothing
    /// interrupts them about it.
    private func runFormatter(on id: Clip.ID) {
        guard let clip = panel?.clips.first(where: { $0.id == id }), let language = clip.language
        else { return }

        Task { [formatter] in
            guard let produced = await formatter.format(clip.text, as: language) else {
                Self.log.info("formatter produced nothing for \(language.rawValue, privacy: .public)")
                return
            }
            guard FormatterGuard.isFaithful(produced, to: clip.text) else {
                // The one outcome worth logging loudly. If this ever fires, a formatter on
                // this machine is changing what code means, and the guard is the only
                // reason it did not reach the clipboard.
                Self.log.error(
                    "formatter output discarded: not faithful (\(language.rawValue, privacy: .public))"
                )
                return
            }
            guard produced != clip.text else { return }
            panel?.sheet = .formatting(id, formatted: produced)
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
        }
    }

    /// Notes that a clip has just been reached for, so eviction can rank by use.
    ///
    /// Called by ``insert(_:richText:used:)``, ``putOnClipboard(_:richText:used:)`` and
    /// ``insertImage(_:)`` rather than by their callers, so that no path can put a clip
    /// somewhere and forget to say so. Its `used:` parameters have no default for the same
    /// reason: a caller with nothing to name must write `used: nil` and mean it.
    ///
    /// That shape was learned the hard way twice over. This method existed, complete and
    /// documented, and **nothing called it** — a scripted edit that should have added five
    /// call sites failed silently before writing them, and an unused private method raises
    /// no warning, so it compiled, shipped, and left `lastUsedAt` frozen at the arrival
    /// time on every clip. Least-recently-used had quietly degraded into
    /// least-recently-*copied*, which is the rule it was introduced to replace. Found by
    /// pasting three clips through the real panel and seeing that not one of seventy-eight
    /// records had moved.
    ///
    /// What is *not* here is merely arrowing past a row: looking at a list is not using
    /// what is in it, and counting it would make the ordering a record of scrolling.
    ///
    /// Fire and forget. The write is bookkeeping for a future eviction and the store
    /// swallows its own failure; making the paste wait on it would trade the thing the
    /// user asked for against the note about it.
    private func markUsed(_ id: Clip.ID?) {
        guard let id else { return }
        let window = retention
        Task { [clipboard] in
            await clipboard.markUsed(id, at: Date(), keeping: window)
        }
    }

    /// K4 — puts a picture where the caret is.
    ///
    /// Its own path because a picture is not a string: it goes on the pasteboard as image
    /// data and is pasted with the same ⌘V the text route uses. The Accessibility
    /// strategy has nothing to offer here — it writes strings — so this does not pretend
    /// to try it.
    private func insertImage(_ clip: Clip) {
        markUsed(clip.id)
        Task { [clipboard, clipboardWatcher] in
            guard let image = clip.image, let data = await clipboard.imageData(for: image) else {
                // B8 again, from the other side: the file went between the row being drawn
                // and the key being pressed.
                Self.log.error("picture missing at paste: \(clip.id, privacy: .public)")
                return
            }
            // No text to name, so the count is all this one has to go on.
            clipboardWatcher.ignoreNextWrite()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(data, forType: .png)
            do {
                try CGEventKeystrokeSender().sendPaste()
            } catch let failure as TextInsertionError {
                // The picture is on the clipboard either way, which is the floor the text
                // path also lands on: the user can press ⌘V themselves.
                Self.log.error(
                    "picture paste refused: \(failure.userMessage, privacy: .public)")
            }
        }
    }

    /// I4 — keeps a finished dictation in the clipboard as well as in the dictation
    /// history.
    ///
    /// The two lists answer different questions: the history is what you have said, and
    /// the clipboard is what you can put somewhere. A dictation belongs in both, and
    /// nothing else puts it in the second — the pasteboard watcher never sees it, because
    /// a dictation inserted through Accessibility never touches the clipboard at all.
    /// Removes the clipboard's copies of a transcript the user has just forgotten.
    ///
    /// Matched on the words rather than on an identifier, because a clip carries no link
    /// back to the dictation that made it. Matching this way can take two clips when the
    /// same sentence was dictated twice — which is the right direction to be wrong in:
    /// the user asked for those words to be gone, and leaving one behind because it came
    /// from a different occasion is not something they would thank us for.
    ///
    /// Only Uttrflow's own clips. Something the user copied by hand that happens to read
    /// the same is theirs, and this button was not about it.
    private func forgetClips(saying spoken: String) async {
        let retention = ClipRetention(
            days: settings.clipboardRetentionDays, now: Date(),
            dictationDays: settings.transcriptRetentionDays)
        let copies = await clipboard.clips(keeping: retention)
            .filter { $0.origin == .uttrflow && $0.text == spoken }
        for copy in copies {
            _ = try? await clipboard.delete(copy.id, keeping: retention)
        }
        await refreshPanelIfOpen()
    }

    private func recordAsClip(_ text: String) {
        Task { [clipboard] in
            let kind = ClipKindDetector.kind(of: text)
            let clip = Clip(
                text: text, kind: kind, copiedAt: Date(), source: ClipOrigin.dictationSource,
                // Which is what keeps it out of History and under the tab beside it. A
                // dictation happens far more often than a ⌘C, so in one list it would be
                // the newest thing every time and the panel would stop being a clipboard.
                origin: .uttrflow,
                language: kind == .code ? CodeLanguage.detect(text) : nil)
            _ = try? await clipboard.record(clip, keeping: retention)
            await refreshPanelIfOpen()
        }
    }

    /// Puts the chosen text where the caret is, by whichever route works.
    ///
    /// The same coordinator a dictation goes through, for the same reason: the three
    /// strategies end in one that cannot fail, so the worst outcome is the words sitting
    /// on the clipboard rather than nowhere.
    private func insert(_ text: String, richText: String? = nil, used: Clip.ID?) {
        markUsed(used)
        Task { [clipInserter] in
            do {
                let method = try await clipInserter.insert(text, richText: richText)
                Self.log.info("clip inserted by \(String(describing: method), privacy: .public)")
            } catch {
                // Every strategy refused, including the one that cannot — so the words
                // are on the clipboard and nowhere else.
                let why = (error as? any UttrflowFailure)?.userMessage ?? String(describing: error)
                Self.log.error("clip insertion failed: \(why, privacy: .public)")
            }
        }
    }

    /// Puts a copy made while the panel is open into the list under the user's eyes.
    ///
    /// The selection survives it, because it is held by identity: the new clip pushes
    /// every row down, and a highlight kept by row number would slide onto the neighbour
    /// of the clip being aimed at.
    private func refreshPanelIfOpen() async {
        guard panel != nil, quickPanel.isVisible else { return }
        let clips = await clipboard.clips(keeping: retention)
        panel?.clips = clips
        guard let snapshot = panel else { return }
        quickPanel.update(PanelPresenter.present(snapshot))
    }

    /// Announced to the watcher first, so a clip Uttrflow puts back is not read as the user
    /// copying it and does not climb to the top of the panel.
    private func putOnClipboard(_ text: String, richText: String? = nil, used: Clip.ID?) {
        markUsed(used)
        clipboardWatcher.ignoreNextWrite(of: text)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        // E2, E3 — both flavours together, so the receiving application takes the one it
        // understands. Pages keeps the headings; a code editor gets the words and never a
        // tag. Choosing for it would mean guessing what it can read, and guessing wrong
        // in the direction of HTML is how `<strong>` ends up in a commit message.
        if let richText { NSPasteboard.general.setString(richText, forType: .html) }
    }

    /// Long enough to read one short sentence, and no longer: the panel is over whatever
    /// the user was doing, and a notice that outstays the reading of it is in the way.
    private static let noticeLingers = Duration.seconds(2.5)

    private func closeAfterReading() {
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: AppDelegate.noticeLingers)
            guard !Task.isCancelled else { return }
            self?.closeQuickPanel()
        }
    }

    private func closeQuickPanel() {
        // A3, A7 — remembered before it is thrown away. The panel is dismissed constantly
        // and by design, so an accidental dismissal must not cost the user their place or
        // the alias they were halfway through typing.
        resume = panel.map {
            PanelResume(
                scope: $0.scope, category: $0.category, selection: $0.selection,
                sheet: $0.sheet, closedAt: Date())
        }
        noticeTask?.cancel()
        quickPanel.hide()
        panel = nil
    }

    // MARK: Relaying

    private func render(_ state: DictationState) {
        getOutOfTheWay(for: state)
        // Recorded before the menu is drawn, so the dictation that has just landed is
        // already in the Recent section the next time the menu bar is clicked. A
        // dictation whose insertion failed is kept too: §19 says the words must stay
        // reachable, and Recent is where ``TextInsertionError/clipboardUnavailable``
        // tells the user to look for them.
        switch state {
        case .inserted(let outcome):
            Self.log.notice(
                """
                dictation finished: method=\(outcome.method.rawValue, privacy: .public) \
                characters=\(outcome.text.count, privacy: .public) \
                app=\(outcome.insertedInto ?? "unknown", privacy: .public) \
                corrections=\(outcome.changes.corrections.count, privacy: .public) \
                snippets=\(outcome.changes.snippets.count, privacy: .public)
                """)
            keep(
                DictationRecord(
                    text: outcome.text, when: Date(), applicationName: outcome.insertedInto,
                    applicationIdentifier: outcome.insertedIntoIdentifier,
                    spokenFor: outcome.spokenFor,
                    changes: RecordedChanges(
                        corrections: outcome.changes.corrections.compactMap {
                            RecordedCorrection(
                                heard: $0.heard, wrote: $0.wrote, wordRange: $0.wordRange,
                                entryID: $0.entryID, reason: $0.reason,
                                heardConfidence: $0.heardConfidence)
                        },
                        snippets: outcome.changes.snippets.map {
                            RecordedSnippet(
                                snippetID: $0.snippetID, matched: $0.matched,
                                expansion: $0.expansion)
                        },
                        spokenWords: outcome.changes.spokenWords)))
            // I4 — and into the clipboard, so a dictation can be pasted a second time
            // without being said again. It is not a copy, so the watcher never sees it and
            // it would otherwise exist only in the dictation history, which is a different
            // list in a different window.
            recordAsClip(outcome.text)
        case .failed(let notice):
            Self.log.error(
                """
                dictation failed: \(notice.message, privacy: .public) \
                salvaged=\(notice.transcript != nil, privacy: .public)
                """)
            if let salvaged = notice.transcript {
                // No changes, and deliberately not an empty set: this dictation never
                // reported what was applied, which is a different fact from "nothing
                // was". `RecordedChanges` being optional is what keeps the accuracy
                // figure from counting an unmeasured dictation as a perfect one.
                keep(DictationRecord(text: salvaged, when: Date()))
            }
        case .idle, .recording, .transcribing, .tidying:
            break
        }

        // Kept because the updater has to know whether a dictation is running, and the
        // pipeline's own state is private to it. Written here, where every change to it
        // already arrives, rather than reached for from somewhere that would have to
        // widen the pipeline's surface to ask.
        lastDictationState = state

        menuBar.update(with: MenuBarPresenter.present(menuBarState(for: state)))
        dock.update(with: DictationPresenter.dock(for: state))
        refreshMainWindow()

        scheduleDismissal(after: state)
    }

    /// Keeps one dictation, on screen at once and on disk shortly after.
    ///
    /// The local echo is not an optimisation: the menu bar is drawn synchronously on the
    /// main actor and cannot await the store, so without it the dictation that just
    /// landed would be missing from Recent until something else redrew it. The store's
    /// answer replaces the echo on the next refresh, which is what keeps retention a
    /// decision made in exactly one place.
    private func keep(_ record: DictationRecord) {
        recents.add(record)
        let days = settings.transcriptRetentionDays
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await history.append(record, keeping: Retention(days: days, now: Date()))
            } catch {
                // Losing the note of a dictation must not disturb the dictation itself,
                // which has already happened and already gone where it was meant to.
                render(.failed(DictationFailure(error)))
            }
        }
    }

    /// Says the pipeline's state in the vocabulary the menu was written against.
    ///
    /// Translation only: every judgement about what the menu then shows, and about what
    /// the user may choose, is made in ``MenuBarPresenter`` where a test can reach it.
    private func menuBarState(for state: DictationState) -> MenuBarState {
        let activity: DictationActivity =
            switch state {
            case .idle, .failed: .idle
            case .recording: .listening
            case .transcribing, .tidying: .working
            case .inserted: .finished
            }
        var failure: FailurePresentation?
        if case .failed(let notice) = state {
            failure = FailurePresenter.present(
                message: notice.message, recovery: notice.recovery, severity: notice.severity)
        }
        return MenuBarState(
            activity: activity,
            failure: failure,
            speechModel: modelStore.isInstalled(.default) ? .ready : .notInstalled,
            recents: recents.previews.map {
                MenuBarRecent(title: $0.title, fullText: $0.dictation.text)
            },
            canCheckForUpdates: UpdateController.isConfigured,
            updateProgress: updates.progress
        )
    }

    /// Carries out whatever the menu was asked for.
    private func carryOut(_ intent: MenuBarIntent) {
        switch intent {
        // Both through the controller, not straight at the pipeline: it is what plays the
        // start and stop cue, and what keeps one answer to "what does a control do" —
        // start if idle, finish if listening. Reaching past it meant the menu could start
        // a dictation the shortcut then could not end.
        case .startDictation, .stopDictation:
            Task { [weak self] in await self?.controller?.toggleFromControl() }
        case .recover(let action):
            perform(action)
        case .insertRecent(let index):
            guard let recent = recents.entries[safe: index] else { return }
            // Through the app's own inserter, not a fresh one. A coordinator built here
            // would get the default pasteboard, and this menu would file a second copy of
            // the dictation under whichever application was in front.
            insert(recent.text, used: nil)
        case .copyRecent(let index):
            guard let recent = recents.entries[safe: index] else { return }
            // And through the helper that announces the write, for the same reason.
            putOnClipboard(recent.text, used: nil)
        case .open(let destination):
            show(destination)
        case .openClipboard:
            Task { await toggleQuickPanel() }
        case .checkForUpdates:
            updates.checkForUpdates()
        case .quit:
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: Windows

    /// Opens whichever surface was asked for.
    ///
    /// One vocabulary and one router: the menu bar, the home page and a failure's
    /// recovery action all name a ``Destination`` and none of them knows which class
    /// owns the window behind it.
    private func show(_ destination: Destination) {
        switch destination {
        case .onboarding:
            // Not `presentOnboardingIfNeeded()`, which returns silently once the flow has
            // been finished. Two live buttons reach here — Home's "Set Up" and the
            // Diagnostics permission row — and both are shown precisely to somebody who
            // has finished onboarding without granting a permission, which the flow
            // allows on purpose. Answering them with nothing at all is the dead button
            // this whole change set exists to remove.
            presentOnboarding(skippingWelcome: true)
        case .settings(let tab):
            settingsWindow.onClose = { [weak self] in self?.redrawMainWindow() }
            settingsWindow.show(tab, identity: signedInIdentity)
            // So the sidebar's Settings row lights up as the window appears rather than
            // at whatever unrelated moment redraws the main window next.
            redrawMainWindow()
        case .main(let tab):
            let window = mainWindow ?? makeMainWindow()
            mainWindow = window
            window.show(tab)
            refreshMainWindow()
        }
    }

    func makeMainWindow() -> MainWindowController {
        let window = MainWindowController(content: mainContent(measurements: []))
        window.onIntent = { [weak self] intent in self?.carryOut(intent) }
        window.onSearch = { [weak self] query in
            guard let self, let page = mainWindow?.page else { return }
            queries[page] = query
            redrawMainWindow()
        }
        window.onScope = { [weak self] scope in
            guard let self, let page = mainWindow?.page else { return }
            scopes[page] = scope
            redrawMainWindow()
        }
        window.onDraft = { [weak self] in
            guard let self else { return }
            // A refusal describes the attempt they made. The moment they change what they
            // typed it describes nothing, and leaving it up would be the page arguing
            // with a word it has not seen.
            wordRefusal = nil
            snippetRefusal = nil
            redrawMainWindow()
        }
        return window
    }

    /// Redraws from what was last read, without going back to disk.
    ///
    /// What a keystroke gets. ``refreshMainWindow()`` re-reads the history, both stores
    /// and both permission gates, which is right after something has changed and absurd
    /// between two letters of a word — it would put three file reads and two system
    /// calls behind every character typed into a search field.
    /// Tells the updater what the app is in the middle of.
    ///
    /// Called from the same place the window is redrawn, which is every time any of the
    /// four facts could have changed. The rule about what to do with them is
    /// ``UpdateGate`` in `UttrflowUX`, where a test can reach it; nothing is decided here.
    private var updateActivity: UpdateActivity {
        UpdateActivity(
            isDictating: lastDictationState.isBusy,
            isPanelOpen: quickPanel.isVisible,
            isEditing: snippetEditorIsOpen || wordEditorIsOpen,
            isOnboarding: onboarding != nil)
    }

    private func redrawMainWindow() {
        updates.refresh()
        guard let mainWindow else { return }
        mainWindow.update(mainContent(measurements: lastMeasurements))
    }

    /// Redraws the window from a fresh snapshot, if it is open.
    ///
    /// Timings live behind an actor, so this hops; everything else is read on the way
    /// back so all three pages describe the same moment rather than three.
    private func refreshMainWindow() {
        guard mainWindow != nil else { return }
        refreshGeneration += 1
        let reading = refreshGeneration
        Task { [weak self] in
            guard let self else { return }
            let measurements = await diagnostics.recorded
            lastMeasurements = measurements
            let kept = await history.records(
                keeping: Retention(days: settings.transcriptRetentionDays, now: Date()))
            self.kept = kept
            recents = RecentDictations(showing: kept)
            knownWords = await dictionary.allEntries()
            knownSnippets = await snippets.snippets()
            // The signed half of the cached profile. Everything the Account page draws
            // about a plan comes from the backend's copy, never from anything this app
            // decided for itself.
            knownEntitlement = account.profiles.load()?.entitlement
            // Read beside the entitlement rather than at each use, so the corner and the
            // Account page cannot be drawn from two different readings of it.
            knownLocalAccount = account.local.load()
            await refreshPicture()
            await refreshPermissions()
            // A refresh started later has already read newer state and may already have
            // drawn it. Painting this one over the top would put the older reading on
            // screen and leave it there until something unrelated redrew.
            guard reading == refreshGeneration else { return }
            mainWindow?.update(mainContent(measurements: measurements))
        }
    }

    private func mainContent(measurements: [StageMeasurement]) -> MainContent {
        let now = Date()
        // The whole kept history, and `HistoryEntry` is `DictationRecord`, so there is
        // nothing to rebuild. Copying it field by field is what silently dropped
        // `spokenFor` — leaving the words-per-minute figure computed from nothing.
        let entries = kept
        let shortcut = SettingsShortcut.compact(settings.hotkey)
        let changed = CorrectionHistory(of: entries)
        let corrections = changed.corrections

        return MainContent(
            home: HomePresenter.page(
                for: HomeSnapshot(
                    permissions: knownPermissions, entries: entries,
                    account: knownEntitlement?.account,
                    local: knownLocalAccount,
                    // The name macOS knows them by, when there is no account to ask.
                    // Read here rather than in the presenter, so a test decides what the
                    // page is greeting rather than inheriting whoever is running it.
                    systemName: NSFullUserName(),
                    shortcut: shortcut, settings: settings, now: now)),
            sidebar: SidebarPresenter.sidebar(
                for: SidebarSnapshot(
                    // The page the main window is showing, whatever else is on the
                    // desktop. Settings is a window rather than a page and lights
                    // nothing; see `SidebarPresenter.isSelected`.
                    selection: .page(mainWindow?.page ?? .home),
                    entries: entries,
                    correctionsToday: corrections.filter {
                        Calendar.autoupdatingCurrent.isDate($0.when, inSameDayAs: now)
                            && !$0.isUndone
                    }.count,
                    shortcutKeys: SettingsShortcut.keycaps(for: settings.hotkey), settings: settings,
                    version: .ofThisBuild,
                    now: now)),
            dictation: DictationPresenter.page(
                for: DictationSnapshot(
                    permissions: knownPermissions, entries: entries, corrections: corrections,
                    query: query(for: .dictation), shortcut: shortcut,
                    settings: settings, now: now)),
            history: HistoryPresenter.page(
                for: HistorySnapshot(
                    entries: entries, query: query(for: .history), settings: settings,
                    keepsRecordings: false, now: now)),
            dictionary: DictionaryPresenter.page(
                for: DictionarySnapshot(
                    entries: knownWords, draft: wordDraft, refusal: wordRefusal,
                    query: query(for: .dictionary), now: now)),
            corrections: CorrectionsPresenter.page(
                for: CorrectionsSnapshot(
                    corrections: corrections, dictations: entries,
                    query: query(for: .corrections),
                    scope: CorrectionsScope(rawValue: scope(for: .corrections)) ?? .all,
                    settings: settings,
                    now: now)),
            insights: InsightsPresenter.page(
                for: InsightsSnapshot(
                    entries: entries, settings: settings, now: now)),
            snippets: SnippetsPresenter.page(
                for: SnippetsSnapshot(
                    snippets: knownSnippets, draft: snippetDraft, refusal: snippetRefusal,
                    query: query(for: .snippets), now: now)),
            style: StylePagePresenter.page(
                for: StylePageSnapshot(
                    settings: settings, capabilities: SettingsCapabilities.everything)),
            diagnostics: DiagnosticsPresenter.page(
                for: DiagnosticsSnapshot(
                    engines: settings.engines, permissions: knownPermissions,
                    measurements: measurements)),
            account: AccountPagePresenter.page(
                for: AccountPageSnapshot(
                    entitlement: knownEntitlement,
                    access: EntitlementGate(profiles: account.profiles, local: account.local)
                        .access(at: now, networkIsReachable: network.isReachable),
                    now: now,
                    picture: knownPicture?.bytes,
                    local: knownLocalAccount)))
    }

    /// What one page is filtered by. Empty for a page never searched.
    ///
    /// Asked per page rather than once for the page on screen. `mainContent` builds all
    /// nine presentations on every redraw, so handing them all the current page's query
    /// filtered every other page by it — which is how a search on History arrived on
    /// Dictionary reporting that no word looks or sounds like "invoice", even after the
    /// queries themselves were stored separately.
    private func query(for page: MainTab) -> String { queries[page] ?? "" }
    private func scope(for page: MainTab) -> String { scopes[page] ?? "" }
    /// Whether an inline editor is open — **not** what is in it.
    ///
    /// The text belongs to the window, which is where it is typed; keeping a second copy
    /// here is how the Save button came to be permanently disabled, because the copy the
    /// presenter read never changed. The app decides whether there is an editor, the
    /// window decides what it says, and neither answers the other's question.
    /// What the dictation pipeline last reported. See where it is written.
    private var lastDictationState: DictationState = .idle
    private var snippetEditorIsOpen = false
    /// The same, for the word editor.
    private var wordEditorIsOpen = false
    /// Why the last Save was refused, per editor, until the user types again.
    ///
    /// Cleared on the next keystroke rather than left standing: the sentence is about the
    /// attempt they made, and once they change what they typed it is about nothing.
    private var wordRefusal: String?
    private var snippetRefusal: String?

    /// Counts every request to open or close an editor.
    ///
    /// `.addSnippet` opens one immediately; `.editSnippet` has to read the store first,
    /// and a disk read is long enough to click something else in. Without this, clicking
    /// Edit and then New Snippet gave a blank form that silently filled itself with the
    /// row's text a moment later — and because the draft carried `editing:`, pressing
    /// Save then edited that row instead of creating a snippet. Two rapid Edits could
    /// also resolve out of order and open the wrong row.
    private var editorGeneration = 0
    /// The same, for redraws. Every refresh suspends six times before it writes to the
    /// window, so two overlapping ones can land in the reverse of the order they started
    /// and repaint from the older reading — a row just deleted reappearing and staying
    /// until something unrelated happens. The pattern is already used for installs,
    /// sign-ins and microphone checks.
    private var refreshGeneration = 0

    /// What the snippet editor currently says, or nothing when it is shut.
    private var snippetDraft: SnippetDraft? {
        snippetEditorIsOpen ? mainWindow?.snippetDraft : nil
    }

    /// What the word editor currently says, or nothing when it is shut.
    private var wordDraft: DictionaryDraft? {
        wordEditorIsOpen ? mainWindow?.wordDraft : nil
    }

    /// What the two stores held at the last refresh.
    ///
    /// Cached for the same reason ``knownPermissions`` is: both stores are actors and a
    /// page is built synchronously. They start empty and are only ever filled in by
    /// ``refreshMainWindow()``, so a page drawn before the first read shows an empty
    /// dictionary — which is what an unread store honestly is, and is corrected within
    /// the same run loop.
    private var knownWords: [DictionaryEntry] = []
    private var knownSnippets: [Snippet] = []
    private var knownEntitlement: Entitlement?
    /// The choice to work without an account, when somebody made it. Drawn by the corner
    /// chip and the Account page; consulted by neither when ``knownEntitlement`` is set.
    private var knownLocalAccount: LocalAccount?
    /// The signed-in person's picture, and the path it was fetched from.
    ///
    /// Kept together so the fetch happens once per account rather than once per redraw:
    /// the main window rebuilds all nine pages whenever anything changes, and a request
    /// per rebuild would be a request every time somebody typed in the search field.
    private var knownPicture: (path: String, bytes: Data)?
    /// The timings the last refresh read, so a keystroke can redraw without hopping to
    /// the actor that holds them.
    private var lastMeasurements: [StageMeasurement] = []
    /// Everything the store still keeps, as of the last refresh.
    ///
    /// Distinct from ``recents``, which is the menu's five and nothing more. Drawing the
    /// window's pages from that one made the History page show five dictations and the
    /// Insights figures describe five, however many had been kept.
    private var kept: [DictationRecord] = []

    /// The last answer each permission gate gave.
    ///
    /// Cached rather than read while building a page, because reading is asynchronous
    /// and a page is built synchronously — but it starts empty and is only ever filled
    /// in by ``refreshPermissions()``. A permission that has genuinely not been checked
    /// stays absent, which the pages draw as silence: guessing `.granted` here would
    /// let Home call the app ready without having asked anything.
    private var knownPermissions: [PermissionKind: PermissionStatus] = [:]

    /// Re-reads both gates.
    ///
    /// Done on every refresh rather than once at launch, because the user can grant or
    /// revoke either one in System Settings while the app is running and the window
    /// must not keep telling them to fix something they have already fixed.
    /// Fetches the signed-in person's picture, at most once per account.
    ///
    /// Guarded on the path rather than on having *a* picture: signing in as somebody else
    /// changes the path, and a guard on "do we have one" would leave the first person's
    /// face over the second person's name. Signing out clears it, because a cached face
    /// outliving its session is the same bug the other way round.
    ///
    /// Failure is silence. The page draws initials while this is outstanding and initials
    /// if it never succeeds, which are the same pixels — so there is nothing to report and
    /// nobody to report it to.
    /// Who is signed in, as the rail at the foot of the Settings window draws them.
    ///
    /// Read from the same entitlement and the same picture the Account page uses, so the
    /// two windows cannot show different people.
    /// Read from the cached profile rather than from ``knownEntitlement``, which is only
    /// filled in once the main window has been drawn: Settings can be opened from the menu
    /// bar on a launch where that never happened, and a rail with no name on it would be
    /// the only place in the app that did not know who was signed in.
    private var signedInIdentity: AccountIdentity? {
        guard let account = account.profiles.load()?.account else { return nil }
        return AccountPagePresenter.identity(for: account, picture: knownPicture?.bytes)
    }

    private func refreshPicture() async {
        guard let path = account.profiles.load()?.account.avatarPath else {
            knownPicture = nil
            return
        }
        guard knownPicture?.path != path else { return }
        guard let bytes = await account.authentication.avatar(at: path) else { return }
        knownPicture = (path, bytes)
    }

    private func refreshPermissions() async {
        let gates: [any PermissionGate] = [
            MicrophonePermissionGate(), AccessibilityPermissionGate(),
        ]
        var latest: [PermissionKind: PermissionStatus] = [:]
        for gate in gates {
            latest[gate.kind] = await gate.status()
        }
        knownPermissions = latest
    }

    /// Carries out whatever a page asked for.
    ///
    /// Internal rather than private so that `UttrflowTests` can drive it. This is the one
    /// switch every control in the main window passes through, and "wiring only" is a
    /// claim worth checking rather than asserting.
    ///
    /// `MainIntentWiringTests` covers the cases that change stored data. The rest — the
    /// ones that open a window, reach the pasteboard or insert into another app — are
    /// not covered there, because each needs the thing it drives.
    func carryOut(_ intent: MainIntent) {
        switch intent {
        case .recover(let action): perform(action)
        case .go(let destination): show(destination)
        case .copy(let text): putOnClipboard(text, used: nil)
        case .insert(let text): insert(text, used: nil)
        case .show(let page):
            mainWindow?.show(page)
            // The sidebar's highlight and its badge are part of the drawn page, so
            // changing page has to redraw. Synchronously from what was last read: nothing
            // on disk changed, and re-reading three files to move between tabs would put
            // a pause on every click.
            redrawMainWindow()
        case .change(let change): apply(change)

        case .forgetDictation(let id):
            let retention = Retention(days: settings.transcriptRetentionDays, now: Date())
            act { [weak self] in
                guard let self else { return }
                // Every finished dictation is written to two files: History, and the
                // clipboard store as a second copy. Removing it from one and leaving the
                // whole transcript in the other is not forgetting it — and the second
                // copy is reachable from the panel, so the words the user just deleted
                // were still one shortcut away.
                let spoken = await self.history.records(keeping: retention)
                    .first { $0.id == id }?.text
                try await self.history.delete(id, keeping: retention)
                if let spoken { await self.forgetClips(saying: spoken) }
            }

        case .addWord:
            editWord(DictionaryDraft())
        case .cancelWordEdit:
            editWord(nil)
        case .saveWord(let word, let pronunciation):
            saveWord(word, pronunciation: pronunciation)
        case .forgetWord(let id):
            act { try await self.dictionary.remove(id) }
        case .restoreWord(let id):
            act { try await self.dictionary.restore(id) }

        case .addSnippet:
            editSnippet(SnippetDraft())
        case .editSnippet(let id):
            // From the store rather than from `knownSnippets`, which is the last refresh
            // and can be a snippet behind: opening the editor on a row added since would
            // find nothing and silently do nothing at all.
            editorGeneration += 1
            let opening = editorGeneration
            Task { [weak self] in
                guard let self,
                    let snippet = await snippets.snippets().first(where: { $0.id == id }),
                    // Anything the user did while the disk was being read wins. Opening
                    // now would overwrite a form they have already moved on from.
                    opening == editorGeneration
                else { return }
                editSnippet(
                    SnippetDraft(editing: id, trigger: snippet.trigger, text: snippet.expansion))
            }
        case .cancelSnippetEdit:
            editSnippet(nil)
        case .saveSnippet(let trigger, let text, let replacing):
            saveSnippet(trigger: trigger, text: text, replacing: replacing)
        case .forgetSnippet(let id):
            act { try await self.snippets.delete(id) }

        case .signIn:
            // Onboarding already owns the whole sign-in conversation — the challenge, the
            // browser, the wait for the backend to say it finished, and every way it can
            // fail. Somebody signed out has nothing else outstanding, so the flow opens
            // on sign-in; a second implementation here would be a second set of those
            // failure paths to keep correct.
            //
            // Said explicitly, because somebody working on this Mac has an account as far
            // as the rest of the flow is concerned, and the page they just asked for
            // would otherwise be the one page it walked past.
            presentOnboarding(skippingWelcome: true, askingToSignIn: true)
        case .signOut:
            // Local data deliberately survives. `ProfileCache` is the only thing this can
            // reach, so there is no path from here to somebody's history even by mistake.
            //
            // The cache is cleared first and the server told afterwards, in the background:
            // somebody asking to be signed out is signed out whatever the network is doing,
            // and the session expires on its own if the request never lands.
            account.profiles.clear()
            Task { [account] in await account.authentication.signOut() }
            refreshMainWindow()

        case .undoCorrection(let id):
            // Two stores, in order, and the order matters: the history decides whether
            // there was anything to undo, and only then is the dictionary told its word
            // was wrong. Counting the revert first would let a stale row on screen retire
            // a word that nothing had actually corrected.
            let retention = Retention(days: settings.transcriptRetentionDays, now: Date())
            Task { [weak self] in
                guard let self,
                    let entryID = try? await history.undoCorrection(id, keeping: retention)
                else { return }
                _ = try? await dictionary.recordRevert(of: entryID)
                refreshMainWindow()
            }

        case .flagDictation(let id):
            let retention = Retention(days: settings.transcriptRetentionDays, now: Date())
            act { try await self.history.toggleFlag(id, keeping: retention) }
        }
    }

    /// Applies a setting changed from the main window.
    ///
    /// Goes through ``SettingsEditor`` exactly as the settings window does, so a choice
    /// offered on two screens cannot be applied two ways. A rejection leaves the
    /// settings untouched — the editor guarantees that — and the redraw puts the control
    /// back where it was, which is the honest report that the change did not happen.
    private func apply(_ change: SettingsChange) {
        // The one change that alters nothing and so cannot go through the editor: it is
        // a request to act now. Handled before the editor rather than after, because
        // there is no updated `Settings` for the rest of this method to save.
        if case .checkForUpdatesNow = change {
            updates.checkForUpdates()
            return
        }

        guard let updated = try? SettingsEditor.apply(change, to: settings) else {
            refreshMainWindow()
            return
        }
        settingsStore.save(updated)
        settingsChanged(to: updated)
    }

    /// Runs a store change and redraws from what the store then holds.
    ///
    /// Never from the value the call returns. Both stores answer with the new list as a
    /// convenience, but taking it here would make this the second thing deciding what is
    /// on disk; ``refreshMainWindow()`` re-reads, so the store stays the only one.
    ///
    /// A failure is logged and swallowed. Every caller is a button on a row that is
    /// already on screen, and the honest report of "the file could not be written" is
    /// that the row is still there after the redraw.
    private func act(_ change: @escaping () async throws -> Void) {
        Task { [weak self] in
            do {
                try await change()
            } catch {
                Self.log.error("store change failed: \(error.localizedDescription, privacy: .public)")
            }
            self?.refreshMainWindow()
        }
    }

    /// Adds a word, and closes the editor only once it is in.
    ///
    /// Every rule about what a word may be lives in the store, which is what makes it
    /// testable. The one decision here is that a refusal leaves the editor open holding
    /// what was typed, rather than closing over a word that was never saved.
    /// Opens or closes the inline word editor, in both places that track it — as
    /// ``editSnippet(_:)`` does, and for the same reason.
    private func editWord(_ draft: DictionaryDraft?) {
        editorGeneration += 1
        wordEditorIsOpen = draft != nil
        wordRefusal = nil
        mainWindow?.editWord(draft)
        refreshMainWindow()
    }

    private func saveWord(_ word: String, pronunciation: String) {
        Task { [weak self] in
            guard let self else { return }
            do throws(DictionaryStoreError) {
                try await dictionary.add(word: word, pronunciation: pronunciation, at: Date())
                editWord(nil)
            } catch {
                Self.log.error("could not add word: \(error.userMessage, privacy: .public)")
                wordRefusal = error.userMessage
                refreshMainWindow()
            }
        }
    }

    /// Opens or closes the inline snippet editor, in both places that track it.
    ///
    /// The window holds what is being typed and the app holds whether it is open; one
    /// call sets both so they cannot disagree about whether there is an editor.
    private func editSnippet(_ draft: SnippetDraft?) {
        editorGeneration += 1
        snippetEditorIsOpen = draft != nil
        snippetRefusal = nil
        mainWindow?.editSnippet(draft)
        refreshMainWindow()
    }

    /// Saves a snippet, and closes the editor only once it is in — as ``saveWord(_:pronunciation:)``
    /// does, and for the same reason.
    private func saveSnippet(trigger: String, text: String, replacing: UUID?) {
        Task { [weak self] in
            guard let self else { return }
            do throws(SnippetStoreError) {
                try await snippets.save(
                    trigger: trigger, expansion: text, replacing: replacing, created: Date())
                editSnippet(nil)
            } catch {
                Self.log.error("could not save snippet: \(error.userMessage, privacy: .public)")
                snippetRefusal = error.userMessage
                refreshMainWindow()
            }
        }
    }

    /// Follows a setting the user has just changed.
    /// Internal so `UttrflowTests` can drive it. Three switches reached nothing at all
    /// until recently, and this is the one place that acts on a settings change.
    func settingsChanged(to updated: Settings) {
        let previous = settings
        settings = updated
        applyAppearance()
        applyLaunchAtLogin()

        // Both of these were drawn and never acted on, which is the worst shape a setting
        // can take: the shortcut row relabelled itself, the menu bar relabelled itself,
        // the home screen changed its instructions — and the key that actually worked was
        // still the old one, until the next launch.
        //
        // `startWatchingForTheShortcut` had exactly one caller, in
        // `applicationDidFinishLaunching`, and `DictationController.setActivation` had
        // none at all outside its own tests.
        if updated.hotkey != previous.hotkey {
            startWatchingForTheShortcut()
        }
        if updated.hotkeyActivation != previous.hotkeyActivation {
            let activation = updated.hotkeyActivation
            Task { [weak self] in await self?.controller?.setActivation(activation) }
        }
        // Same failure as the two above, avoided: `setInstallsAutomatically` existed with
        // no caller anywhere outside its own tests, so the switch would have drawn itself
        // and changed nothing.
        if updated.installsUpdatesAutomatically != previous.installsUpdatesAutomatically {
            updates.setInstallsAutomatically(updated.installsUpdatesAutomatically)
        }

        dock.setShortcut(SettingsShortcut.compact(settings.hotkey))
        if settings.showsFloatingButton {
            dock.setAnchor(settings.floatingButtonAnchor)
            dock.show()
        } else {
            dock.hide()
        }
        refreshMainWindow()
    }

    /// Hides the main window while the user is speaking, if they asked for that.
    ///
    /// "Get Uttrflow out of the way while I dictate" is what the switch says, and it did
    /// nothing: `MainWindowController.hide()` was written for it — its documentation says
    /// so — and nothing ever called it. Somebody dictating into a window behind Uttrflow's
    /// could not see the words land, which is the whole reason the setting exists.
    ///
    /// It hides and does not come back. `orderOut` keeps the window's page and size, so
    /// reopening returns the user where they were — but reopening it *for* them would
    /// take the foreground away from the application they just dictated into, at the
    /// exact moment they are reading what arrived there.
    private func getOutOfTheWay(for state: DictationState) {
        guard settings.minimisesWhileDictating, case .recording = state else { return }
        mainWindow?.hide()
    }

    /// Draws the app light, dark, or however the Mac is set.
    ///
    /// Set on the application rather than per window, so every window Uttrflow owns — the
    /// main one, settings, onboarding, the floating button and the clipboard panel —
    /// changes together. A single window left behind on the old appearance is worse than
    /// not offering the choice.
    ///
    /// `nil` is how AppKit spells "follow the Mac"; it is not the absence of a choice.
    private func applyAppearance() {
        NSApplication.shared.appearance =
            switch settings.appearance {
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            case .system: nil
            }
    }

    /// Tells macOS whether to start Uttrflow at login.
    ///
    /// `LaunchAtLogin` was built, tested and never called. "Open Uttrflow at login" was
    /// stored, drawn and toggled, and the system was never told — so the switch did
    /// nothing at all, and reported that it had.
    ///
    /// Compared against what macOS currently believes rather than applied unconditionally,
    /// because this runs on every settings change and on launch. `SMAppService` throws
    /// when asked for something it already has, which is not a failure but is noise.
    ///
    /// The answer is the state that follows, not the state asked for: macOS can refuse an
    /// unsigned or relocated build and say nothing. A refusal is logged rather than shown
    /// — the switch reads the real status back through `SettingsCapabilities`, so the user
    /// sees the truth on the next draw rather than an alert about it.
    private func applyLaunchAtLogin() {
        guard loginItem.isEnabled != settings.opensAtLogin else { return }
        let became = settings.opensAtLogin ? loginItem.enable() : loginItem.disable()
        if (became == .enabled) != settings.opensAtLogin {
            Self.log.error(
                "macOS refused the login item: asked for \(self.settings.opensAtLogin, privacy: .public), got \(String(describing: became), privacy: .public)"
            )
        }
    }

    /// Returns the interface to rest once the user has had time to read the result.
    private func scheduleDismissal(after state: DictationState) {
        dismissalTask?.cancel()
        let linger: Duration
        switch state {
        case .inserted: linger = Self.successLingers
        // An informational notice is not asking the user to do anything — "Didn't catch
        // that" wants to be seen and then gone. Holding it for the ten seconds a real
        // failure needs would put a panel over the corner of their screen every time the
        // microphone missed a word.
        case .failed(let notice):
            linger = notice.severity == .informational ? Self.successLingers : Self.failureLingers
        case .idle, .recording, .transcribing, .tidying: return
        }

        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: linger)
            guard !Task.isCancelled else { return }
            await self?.pipeline?.acknowledge()
        }
    }

    /// Carries out the one thing a failure offered the user.
    private func perform(_ action: RecoveryAction) {
        switch action {
        case .openSystemSettings(let pane):
            Task { await openSettingsPane(pane) }
        case .retry:
            // Not a synthesised keypress. `submit(.pressed)` with no release opened the
            // microphone and, in hold-to-talk, left nothing able to close it: the next
            // real hold was refused as busy and its release finished this recording
            // instead, inserting everything heard in between.
            Task { [weak self] in await self?.controller?.toggleFromControl() }
        case .downloadSpeechModel:
            // Installing a model needs a window to show progress in. It has one now.
            show(.settings(.dictation))
        case .pasteManually:
            // The words are already on the clipboard: the insertion floor put them
            // there before reporting failure. Acknowledging clears the notice.
            Task { await pipeline?.acknowledge() }
        case .showRecentDictations:
            // Nothing to copy — the clipboard is what failed. Opening the menu puts the
            // Recent section, which does have the words, under the user's pointer. The
            // notice is left to its own timer rather than acknowledged here, because
            // acknowledging redraws the menu bar item and would shut the menu again.
            menuBar.openMenu()
        }
    }

    private func openSettingsPane(_ pane: SystemSettingsPane) async {
        switch pane {
        case .accessibility:
            let outcome = await AccessibilityPermissionGate().request()
            // Fn is watched, not registered, and watching another app's keys needs this
            // grant. The Carbon path needs no permission at all, so a shortcut that
            // failed to arm was never a thing that could happen before Fn existed — and
            // the failure is reported once, as a transient notice, and never retried.
            // Somebody who granted Accessibility when asked would have had a dictation
            // key that did nothing for the rest of the session, and worked after a
            // relaunch, with nothing connecting the two.
            if outcome == .granted, settings.hotkey.heldModifier != nil {
                startWatchingForTheShortcut()
            }
        case .microphone, .appleIntelligence:
            _ = await MicrophonePermissionGate().request()
        }
    }
}

// MARK: - The pipeline's seams, wired to the real stores

/// The correction engine, reading the user's own dictionary.
///
/// Mapping only. Which words may be replaced is `WordCorrectionEngine`'s decision, which
/// entries could be meant is `PhoneticIndex`'s, and whether a proposal is used at all is
/// the pipeline's — this names the three and translates between their vocabularies.
private struct DictionaryCorrections: WordCorrecting {
    let dictionary: PersonalDictionaryStore
    let engine = WordCorrectionEngine()

    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async -> [DictationCorrection] {
        // No score, no judgement. Whisper reports one and Apple's recogniser does not,
        // so a build using the latter simply gets no corrections — the honest outcome
        // rather than a degraded one. Returning here also keeps the dictionary off the
        // hot path entirely when there is nothing to ask it about.
        guard let scored = transcription.scoredWords else { return [] }
        let utterance = Utterance(
            words: scored.map { SpokenWord(text: $0.text, confidence: $0.confidence) })

        let proposals = await engine.proposals(
            for: utterance, against: dictionary.index(), seeing: context)

        return proposals.map {
            DictationCorrection(
                heard: $0.heard, wrote: $0.replacement, wordRange: $0.wordRange,
                entryID: $0.entryID, reason: $0.reason.rawValue,
                heardConfidence: $0.heardConfidence)
        }
    }
}

/// The snippet matcher, built from what is on disk at the moment of the dictation.
private struct StoredSnippets: SnippetExpanding {
    let store: SnippetStore

    func expand(_ text: String) async -> ExpandedTranscript {
        let expansion = await store.expander().expand(text)
        return ExpandedTranscript(
            text: expansion.text,
            snippets: expansion.applied.map {
                SnippetUse(
                    snippetID: $0.snippetID, matched: $0.matched, expansion: $0.expansion)
            })
    }
}

/// Counts a finished dictation back into the two stores it drew on.
private struct StoreCounters: DictationLearning {
    let dictionary: PersonalDictionaryStore
    let snippets: SnippetStore

    func recordUse(ofEntry id: UUID) async throws(DictationChangeError) {
        do {
            _ = try await dictionary.recordUse(of: id)
        } catch {
            throw .storeRefused
        }
    }

    func recordUse(ofSnippets ids: [UUID]) async throws(DictationChangeError) {
        do {
            _ = try await snippets.recordUse(of: ids, at: Date())
        } catch {
            throw .storeRefused
        }
    }
}

/// Lets a finished dictation teach the dictionary a word nobody asked it to learn.
///
/// Mapping only, like the correction seam above it. What is worth learning, and how much
/// evidence it takes, is `LearnableWords`' decision; when it is safe to learn at all is
/// the pipeline's. This names the two and translates between them.
///
/// Internal rather than private so `UttrflowTests` can drive it. `UttrflowPipelineTests`
/// cannot see `UttrflowDictionary` — deliberately, because the pipeline earns the right to
/// be tested without one by depending on none — so the two halves of this seam are proven
/// in separate targets and *this adapter is the only place they meet*. Untested, a swap of
/// `heard` and `wrote` here would compile and silently teach the dictionary the words the
/// user was getting rid of.
struct LearnedVocabulary: VocabularyLearning {
    let dictionary: PersonalDictionaryStore

    func learn(
        heard: String, wrote: String, seeing context: AppContext
    ) async throws(DictationChangeError) {
        do {
            _ = try await dictionary.learn(
                heard: heard, wrote: wrote, seeing: context, at: Date())
        } catch {
            throw .storeRefused
        }
    }
}

/// A menu is built from a snapshot of the list; by the time a click arrives the list may
/// be a dictation longer or shorter, and an index that no longer exists must do nothing
/// rather than take the process down with it.
extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
