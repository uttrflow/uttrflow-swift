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
import UttrflowPredictStore
import UttrflowSettings
import UttrflowSpeech
import UttrflowUX

/// Assembles the product and relays between it and the interface, deciding nothing itself.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// Records which of the three insertion routes a dictation took, which nothing else can tell.
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "insertion")

    private let settingsStore: any SettingsStore = UserDefaultsSettingsStore()
    private var settings = Settings()

    private let menuBar = MenuBarController()
    private let dock = DockPanelController()
    private var recents = RecentDictations()
    /// Where dictations are kept between launches, and the only thing that decides what is deleted.
    private let history: DictationHistoryStore
    /// The user's own words, shared by all three parts of a dictation that read them.
    private let dictionary: PersonalDictionaryStore
    private let snippets: SnippetStore
    /// The account layer, made once and shared, because a second one signs with a different key.
    private let account = OnboardingAccountLayer.forThisBuild()
    /// Whether a renewal could be attempted, which only changes what the Account page says.
    private let network: any NetworkReachability = SystemNetworkReachability()
    /// What macOS is told about starting at login, held so a test can stand in for the system.
    private let loginItem: LaunchAtLogin
    /// Read before decoding and again for the tidier, shared so the second read is the warm one.
    private let context = MacContextEngine()
    /// Held, because the menu asks whether the model is ready every time it is drawn.
    private let modelStore = FileSystemSpeechModelStore.whisperKit()

    /// Keeps the pipeline's stage timings for the session, which is what the diagnostics page reports on.
    private let diagnostics = DiagnosticsRecorder()

    /// Whether the recogniser can dictate, which is not whether its files are on disk.
    private var speechReadiness: SpeechModelReadiness = .notInstalled

    /// How the recording in progress is going against ``DictationLimit``.
    private var recordingAdvice: DictationAdvice = .keepGoing

    private var pipeline: DictationPipeline?
    private var controller: DictationController<ContinuousClock>?
    private var stateTask: Task<Void, Never>?
    private var dismissalTask: Task<Void, Never>?

    // MARK: The clipboard

    private let clipboard: ClipboardStore

    /// Where every local store lives, kept because tab-to-complete opens its corpus after launch.
    private let container: URL

    /// Tab-to-complete, built only where the user has asked for it. See `Docs/predict.md`.
    private var completions: SuggestionCoordinator?

    /// Builds the app around one folder, which a test points at a temporary one.
    init(
        container: URL = .applicationSupportDirectory, loginItem: LaunchAtLogin = LaunchAtLogin()
    ) {
        self.container = container
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

    /// Keeping the app up to date, asking this delegate what it is doing rather than being told.
    private lazy var updates = UpdateController { [weak self] in
        // No delegate means no idea, and no idea means do not interrupt.
        self?.updateActivity ?? UpdateActivity(isDictating: true)
    }
    /// Its own monitor, because sharing one would mean one binding and these are two keys.
    private let clipboardHotkeys = CarbonHotkeyMonitor()
    /// Asked when the panel opens whether a paste can be placed, held so the answer costs one call.
    private let accessibility = AccessibilityPermissionGate()
    private let microphone = MicrophonePermissionGate()
    private let focus: any AccessibilityFocus = AXAccessibilityFocus()
    /// D5 — asked, when the panel opens, which languages have a formatter on this disk.
    private let formatter: any CodeFormatting = SystemCodeFormatter()

    /// The one pasteboard that announces its writes, so no inserter can silently forget to. See `Docs/insertion.md`.
    private lazy var announcingPasteboard = SystemPasteboard {
        [clipboardWatcher] in clipboardWatcher.ignoreNextWrite(of: $0)
    }

    /// Puts a chosen clip where the caret is, announcing the write so it is not read as a copy.
    private lazy var clipInserter = TextInsertion.coordinator(
        pasteboard: announcingPasteboard)

    /// The panel's state while it is open, held here because a window has no memory.
    private var panel: PanelSnapshot?
    private var clipboardWatchTask: Task<Void, Never>?
    private var clipboardHotkeyTask: Task<Void, Never>?

    /// F7, F9 — the clip a delete removed, held by the app because the undo outlives the panel.
    private var undoable: Clip?
    private var undoTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    /// A3, A7 — where the user was when the panel closed, while reopening still counts as undoing.
    private var resume: PanelResume?
    /// Long enough to reach for the keyboard, short enough to not undo a forgotten delete.
    private static let undoWindow = Duration.seconds(8)

    /// Internal so a test can install one and read back what an intent opened it on.
    var mainWindow: MainWindowController?
    /// The settings window over *this* app's stores, never a second set of actors on the same files.
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
    /// What is typed into each page's search field, kept per page because six of them have one.
    private var queries: [MainTab: String] = [:]
    private var scopes: [MainTab: String] = [:]

    /// How long a finished result stays up, so the last dictation does not sit over every app.
    private static let successLingers = Duration.seconds(2)
    /// Longer, because a failure asks something of the user — but it still goes.
    private static let failureLingers = Duration.seconds(10)

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = settingsStore.load()
        // Reconciled at launch too: the login item can be removed without telling the app.
        applyAppearance()
        applyLaunchAtLogin()
        buildPipeline()
        wireInterface()
        startWatchingForTheShortcut()
        startWatchingTheClipboard()
        startCompletingWhatIsTyped()
        loadSpeechModel()
        refreshAccount()
        presentOnboardingIfNeeded()
        // Shown at launch, since a menu-bar icon alone is an interface most people never find.
        if onboarding == nil { show(.main(.home)) }
        // Last, from the setting: an update check here would race the model download.
        updates.onProgressChanged = { [weak self] in self?.refreshMenuBar() }
        updates.begin(automatically: settings.installsUpdatesAutomatically)
    }

    /// Loads the recogniser, saying so until it can dictate. See `Docs/startup.md`.
    private func loadSpeechModel() {
        guard modelStore.isInstalled(.default) else {
            speechReadiness = .notInstalled
            return
        }
        speechReadiness = .loading
        refreshMenuBar()
        Task { [weak self] in
            await self?.pipeline?.prepare()
            guard let self, let pipeline else { return }
            speechReadiness = await pipeline.isReady ? .ready : .notInstalled
            refreshMenuBar()
        }
    }

    /// Redraws the menu bar from whatever the app currently knows.
    private func refreshMenuBar() {
        menuBar.update(with: MenuBarPresenter.present(menuBarState(for: lastDictationState)))
    }

    /// Re-reads the account in the background at launch, which nothing waits for. See `Docs/entitlements.md`.
    private func refreshAccount() {
        Task { [account] in
            let outcome = await account.refresh.run()
            // Only a change is worth a redraw; `unchanged` is the common answer.
            guard outcome == .updated || outcome == .signedOut else { return }
            refreshMainWindow()
        }
    }

    /// Clicking the Dock icon of an app with no visible window, which must open one.
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

    /// Shows or hides the sidebar's names, and does nothing when there is no window yet.
    @objc func toggleSidebarFromMenu(_ sender: Any?) { mainWindow?.toggleSidebar() }

    /// Names the sidebar item after what choosing it does, which a fixed title gets wrong half the time.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(toggleSidebarFromMenu(_:)) else { return true }
        item.title = mainWindow?.isSidebarExpanded == true ? "Hide Sidebar" : "Show Sidebar"
        return mainWindow != nil
    }

    /// Shows the first-run flow, which the rest of the app is deliberately not gated behind.
    private func presentOnboardingIfNeeded() {
        guard OnboardingWindowController(settingsStore: settingsStore, account: account).isRequired
        else { return }
        presentOnboarding(skippingWelcome: false)
    }

    /// Builds the flow fresh each time, because a finished one would open on its last page.
    private func presentOnboarding(skippingWelcome: Bool, askingToSignIn: Bool = false) {
        let onboarding = OnboardingWindowController(settingsStore: settingsStore, account: account)
        self.onboarding = onboarding
        onboarding.onFinish = { [weak self] _ in
            guard let self else { return }
            // Re-read, because the microphone check writes the language list through the same store.
            settingsChanged(to: settingsStore.load())
            self.onboarding = nil
            // The session is what onboarding changes that the settings store knows nothing about.
            refreshMainWindow()
        }
        // However the window goes, including the red button, which changes the Account page.
        onboarding.onClose = { [weak self] in self?.refreshMainWindow() }
        onboarding.present(skippingWelcome: skippingWelcome, askingToSignIn: askingToSignIn)
    }

    /// How long quitting waits for a dictation to land. See `Docs/quitting.md`.
    private static let quitBudget = Duration.seconds(15)

    /// Finishes the dictation in flight before letting the process die, but not for ever.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let pipeline else { return .terminateNow }

        Task { [weak self, pipeline] in
            // A recording waits on the user, not the app, and the key may never come up.
            if await pipeline.currentState.isListening { await pipeline.finishRecording() }

            _ = try? await withStageTimeout(Self.quitBudget, clock: ContinuousClock()) {
                for await state in await pipeline.states() where !state.isBusy { return }
            }
            await self?.controller?.stop()
            // On every path: an unanswered `terminateLater` is an app that cannot be quit.
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        stateTask?.cancel()
        dismissalTask?.cancel()
        completions?.stop()
    }

    /// Builds tab-to-complete, or leaves it unbuilt, which is what everybody who has not asked for it gets.
    private func startCompletingWhatIsTyped() {
        guard settings.suggestions.isEnabled, completions == nil else { return }
        do {
            let coordinator = try SuggestionCoordinator(
                container: container, preferences: settings.suggestions)
            // ⌥⎋ persists the master switch off, so the screen agrees and turning it back on rebuilds the loop.
            coordinator.onTurnedOffEverywhere = { [weak self] in
                self?.apply(.toggle(.suggestionsEnabled, isOn: false))
            }
            completions = coordinator
            coordinator.start()
        } catch {
            Self.log.error("the corpus would not open: \(String(describing: error), privacy: .public)")
        }
    }

    /// Follows the Suggestions screen: builds the loop, takes it away, or hands it what changed.
    private func suggestionsChanged() {
        guard settings.suggestions.isEnabled else {
            completions?.stop()
            completions = nil
            return
        }
        guard let completions else { return startCompletingWhatIsTyped() }
        completions.follow(settings.suggestions)
    }

    /// Arms the shortcut again when it could not be armed before. See `Docs/shortcuts.md`.
    func applicationDidBecomeActive(_ notification: Notification) {
        guard shortcutFailure != nil else { return }
        startWatchingForTheShortcut()
    }

    // MARK: Assembly

    private func buildPipeline() {
        let model = SpeechModel.default

        let speech = SpeechEngineFactory.make(
            kind: settings.engines.speech, model: model,
            modelFolder: modelStore.location(of: model),
            vocabulary: DictionaryVocabulary { [dictionary, context] in
                // One reading, so the words are ranked against the screen they were ranked for.
                await (dictionary.allEntries(), context.currentContext(), Date())
            })

        // Held so the floating button's meter reads the level without queueing behind a `stop()`.
        let microphone = AVAudioCaptureEngine(
            source: AVAudioEngineMicrophoneSource())
        dock.setLevelSource { microphone.momentaryLevel }

        let pipeline = DictationPipeline(
            capture: microphone,
            speech: speech,
            cleaner: TextTransformers.router(configuration: settings.engines),
            context: context,
            // Announced, like every write this app makes. See `Docs/insertion.md`.
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
            clock: ContinuousClock(),
            onAdvice: { [weak self] advice in
                Task { @MainActor in self?.recordingAdviceChanged(to: advice) }
            }
        )
    }

    /// Redraws the menu bar and the floating button as a recording nears its cap.
    private func recordingAdviceChanged(to advice: DictationAdvice) {
        guard advice != recordingAdvice else { return }
        recordingAdvice = advice
        refreshMenuBar()
        dock.update(with: DictationPresenter.dock(for: lastDictationState, advice: advice))
    }

    private func wireInterface() {
        guard let pipeline else { return }

        menuBar.onCommand = { [weak self] intent in self?.carryOut(intent) }

        // Submitted, not handled: the controller queues gestures so press and release cannot interleave.
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

    /// Stands the shortcut down while a new one is being recorded, since a held modifier is not swallowed.
    private func shortcutRecordingChanged(to isRecording: Bool) {
        if isRecording {
            Task { [weak self] in await self?.controller?.stop() }
        } else {
            startWatchingForTheShortcut()
        }
    }

    /// Why the shortcut is not armed, or `nil` when it is. Retried on the way back in.
    private var shortcutFailure: HotkeyError?

    private func startWatchingForTheShortcut() {
        guard let controller else { return }
        let binding = settings.hotkey
        Task { [weak self] in
            do throws(HotkeyError) {
                try await controller.start(binding: binding)
                self?.shortcutFailure = nil
            } catch {
                self?.shortcutFailure = error
                // Said, not swallowed, and retried when the app is next activated.
                self?.render(.failed(DictationFailure(error)))
            }
        }
    }

    // MARK: The clipboard

    /// How long unkept clips live, read on every use because both the window and now move.
    private var retention: ClipRetention {
        ClipRetention(
            days: settings.clipboardRetentionDays, now: Date(),
            // One control, both copies: the clipboard's copy of a transcript ages by the same setting.
            dictationDays: settings.transcriptRetentionDays)
    }

    private func startWatchingTheClipboard() {
        quickPanel.onKey = { [weak self] key, behind in
            self?.panelAnswered(key, behind: behind)
        }
        quickPanel.onIntent = { [weak self] intent in self?.carryOut(intent) }

        // Built out here: a `[weak self]` closure nested in another captures the outer binding.
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
        // Best-effort: a refused write loses one clip, and giving up would lose all the rest.
        _ = try? await clipboard.record(noticed, keeping: retention)
        await refreshPanelIfOpen()
    }

    /// A second registration for a second key, whose refusal is logged rather than shown as a dictation failure.
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
                // Releases ignored: a window that shut on key-up would punish a slow hand.
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
        // Built fresh, so a revealed secret cannot outlive the panel it was revealed in.
        var snapshot = PanelSnapshot.opening(
            clips: clips, now: Date(), insertion: placement, resuming: resume)
        snapshot.dictation = await voice()
        // K4, B8 — asked once on the way in, so the presenter stays a function of its input.
        snapshot.imagesFolder = await clipboard.imagesFolder
        snapshot.missingImages = await missingPictures(among: clips)
        snapshot.formattableLanguages = await formattable(among: clips)
        // A4 — said on the way in, not after Return, when there is nowhere left to say it.
        if case .clipboardOnly(let obstacle) = placement, obstacle == .accessibilityNotGranted {
            snapshot.notice = obstacle.notice
        }
        panel = snapshot
        quickPanel.show(PanelPresenter.present(snapshot))
    }

    /// B3–B5 — whether Return will place a clip or only copy it, asked while there is still somewhere to say so.
    private func placement() async -> PanelInsertion {
        // The two questions only the machine can answer; the rule is `PanelInsertion.decided`.
        await PanelInsertion.decided(
            isAccessibilityGranted: accessibility.status() == .granted,
            isSelfFrontmost: focus.isSelfFrontmost())
    }

    /// D5 — which languages present in the list have a formatter, asked per language and not per clip.
    private func formattable(among clips: [Clip]) async -> Set<CodeLanguage> {
        var answered: Set<CodeLanguage> = []
        for language in Set(clips.compactMap(\.language)) {
            if await formatter.isAvailable(for: language) { answered.insert(language) }
        }
        return answered
    }

    /// B8 — the picture clips whose files are gone, at one `stat` each and none for text.
    private func missingPictures(among clips: [Clip]) async -> Set<Clip.ID> {
        var missing: Set<Clip.ID> = []
        for clip in clips {
            guard let image = clip.image else { continue }
            if await clipboard.imageData(for: image) == nil { missing.insert(clip.id) }
        }
        return missing
    }

    /// I6, I7 — whether dictation can start and why not, so a dimmed button carries its reason.
    private func voice() async -> PanelDictation {
        guard await microphone.status() == .granted else {
            return .unavailable(.microphoneNotGranted)
        }
        // The same question the menu bar asks: loaded, not merely on disk.
        guard speechReadiness == .ready else {
            return .unavailable(.modelNotReady(percent: nil))
        }
        return .ready
    }

    /// A8 — answers a keystroke, noting first whether the application underneath has quit.
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
            // Stays open, or the sentence would be about a clip the user can no longer see.
            panel?.notice = notice
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            closeAfterReading()
        case .closeAndInsertFormatted(let text, let richText, let used):
            closeQuickPanel()
            insert(text, richText: richText, used: used)
        case .closeAndInsert(let text, let used):
            // Closed first: insertion declines outright while Uttrflow is frontmost.
            closeQuickPanel()
            insert(text, used: used)
        case .copyAndSay(let text, let notice, let used):
            // Stays open: the panel is the only surface left to say this on.
            putOnClipboard(text, used: used)
            panel?.notice = notice
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            closeAfterReading()
        case .applyAndRedraw(let change):
            quickPanel.update(PanelPresenter.present(response.state))
            apply(change)
        }
    }

    /// Carries out a change and redraws from what the store hands back, never from what was asked.
    private func apply(_ change: PanelChange) {
        Task {
            do {
                try await carryOut(change)
            } catch let failure as ClipboardStoreError {
                // F10 — stays open holding the failure, which must look different from a success.
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
            // F7, F9 — kept in hand, because the store forgets it the moment this returns.
            undoable = panel?.clips.first { $0.id == id }
            panel?.canUndoDelete = undoable != nil
            Self.log.info(
                "delete: undoable=\(self.undoable != nil, privacy: .public) flag=\(self.panel?.canUndoDelete == true, privacy: .public)"
            )
            _ = try await clipboard.delete(id, keeping: retention)
            await startForgettingTheUndo()
        case .create(let text):
            // Detected here: the panel knows what was typed, not what a string is.
            let kind = ClipKindDetector.kind(of: text)
            let clip = Clip(
                text: text, kind: kind, copiedAt: Date(), source: nil,
                // Typed into the panel and kept, so it belongs with what the app made.
                origin: .uttrflow,
                language: kind == .code ? CodeLanguage.detect(text) : nil)
            _ = try await clipboard.record(clip, keeping: retention)
        case .rewriteText(let id, let tidied):
            _ = try await clipboard.setText(tidied, of: id, keeping: retention)
        case .setRichText(let id, let note):
            _ = try await clipboard.setRichText(note, of: id, keeping: retention)
        case .renameCategory(let from, let to):
            // Every clip under the old name moves; no alias is touched, because a collection is a shelf.
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

    /// Expires the undo offer, so an old delete cannot be reversed by a keystroke meant for something else.
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
        // Insert and reveal go the path Return goes, so a click and a key mean one clip.
        if let key = intent.key {
            panelAnswered(key)
            return
        }

        switch intent {
        case .pin(let id): setPinned(true, of: id)
        case .unpin(let id): setPinned(false, of: id)
        case .copy(let id):
            // Onto the clipboard and no further: the user will paste it somewhere else.
            guard let clip = panel?.clips.first(where: { $0.id == id }) else { return }
            putOnClipboard(clip.text, richText: clip.richText, used: clip.id)
            closeQuickPanel()
        case .keepQuery(let text):
            apply(.create(text))
        case .dictate:
            // Closed first, then the ordinary dictation, so one place describes it.
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
            // Closed first: Settings activates the app, and the panel would belong to nothing.
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

    /// D5–D7 — runs the formatter and guards its output before anybody is offered a diff.
    private func runFormatter(on id: Clip.ID) {
        guard let clip = panel?.clips.first(where: { $0.id == id }), let language = clip.language
        else { return }

        Task { [formatter] in
            guard let produced = await formatter.format(clip.text, as: language) else {
                Self.log.info("formatter produced nothing for \(language.rawValue, privacy: .public)")
                return
            }
            guard FormatterGuard.isFaithful(produced, to: clip.text) else {
                // Logged loudly: a formatter changing what code means, caught by the guard.
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

    /// Notes a clip was reached for, from the three methods that place one so no path can forget.
    private func markUsed(_ id: Clip.ID?) {
        guard let id else { return }
        let window = retention
        Task { [clipboard] in
            await clipboard.markUsed(id, at: Date(), keeping: window)
        }
    }

    /// K4 — pastes a picture, on its own path because the Accessibility route writes only strings.
    private func insertImage(_ clip: Clip) {
        markUsed(clip.id)
        Task { [clipboard, clipboardWatcher] in
            guard let image = clip.image, let data = await clipboard.imageData(for: image) else {
                // B8 from the other side: the file went between the draw and the keypress.
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
                // On the clipboard either way, which is the floor the text path lands on too.
                Self.log.error(
                    "picture paste refused: \(failure.userMessage, privacy: .public)")
            }
        }
    }

    /// Removes Uttrflow's own clipboard copies of a forgotten transcript, matched on the words.
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
                // Which keeps it out of History, where it would be the newest thing every time.
                origin: .uttrflow,
                language: kind == .code ? CodeLanguage.detect(text) : nil)
            _ = try? await clipboard.record(clip, keeping: retention)
            await refreshPanelIfOpen()
        }
    }

    /// Puts text where the caret is, through the coordinator whose last strategy cannot fail.
    private func insert(_ text: String, richText: String? = nil, used: Clip.ID?) {
        markUsed(used)
        Task { [clipInserter] in
            do {
                let method = try await clipInserter.insert(text, richText: richText)
                Self.log.info("clip inserted by \(String(describing: method), privacy: .public)")
            } catch {
                // Every strategy refused, including the one that cannot.
                let why = (error as? any UttrflowFailure)?.userMessage ?? String(describing: error)
                Self.log.error("clip insertion failed: \(why, privacy: .public)")
            }
        }
    }

    /// Adds a copy made while the panel is open, without moving a selection held by identity.
    private func refreshPanelIfOpen() async {
        guard panel != nil, quickPanel.isVisible else { return }
        let clips = await clipboard.clips(keeping: retention)
        panel?.clips = clips
        guard let snapshot = panel else { return }
        quickPanel.update(PanelPresenter.present(snapshot))
    }

    /// Announced first, so a clip put back is not read as the user copying it.
    private func putOnClipboard(_ text: String, richText: String? = nil, used: Clip.ID?) {
        markUsed(used)
        clipboardWatcher.ignoreNextWrite(of: text)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        // E2, E3 — both flavours, so the receiving application takes the one it understands.
        if let richText { NSPasteboard.general.setString(richText, forType: .html) }
    }

    /// Long enough to read one short sentence, and no longer, since the panel is in the way.
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
        // A3, A7 — remembered before it goes, so an accidental dismissal costs nothing.
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
        // Recorded before the menu is drawn, and kept even when insertion failed. §19.
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
            // I4 — into the clipboard too, which the watcher never sees because this is not a copy.
            recordAsClip(outcome.text)
        case .failed(let notice):
            Self.log.error(
                """
                dictation failed: \(notice.message, privacy: .public) \
                salvaged=\(notice.transcript != nil, privacy: .public)
                """)
            if let salvaged = notice.transcript {
                // Not an empty set: unmeasured is a different fact from nothing changed.
                keep(DictationRecord(text: salvaged, when: Date()))
            }
        case .idle, .recording, .transcribing, .tidying:
            break
        }

        // Kept here, where every change already arrives, so the updater need not ask the pipeline.
        lastDictationState = state

        // Cleared as soon as the recording ends, so a countdown cannot outlive it.
        if !state.isListening { recordingAdvice = .keepGoing }
        menuBar.update(with: MenuBarPresenter.present(menuBarState(for: state)))
        dock.update(with: DictationPresenter.dock(for: state, advice: recordingAdvice))
        refreshMainWindow()

        scheduleDismissal(after: state)
    }

    /// Keeps one dictation, echoed on screen at once because the menu cannot await the store.
    private func keep(_ record: DictationRecord) {
        recents.add(record)
        let days = settings.transcriptRetentionDays
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await history.append(record, keeping: Retention(days: days, now: Date()))
            } catch {
                // Losing the note must not disturb the dictation, which already landed.
                render(.failed(DictationFailure(error)))
            }
        }
    }

    /// Translates the pipeline's state into the menu's vocabulary, deciding nothing.
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
            speechModel: speechReadiness,
            recordingAdvice: recordingAdvice,
            recents: recents.previews.map {
                MenuBarRecent(title: $0.title, fullText: $0.dictation.text)
            },
            canCheckForUpdates: UpdateController.isConfigured,
            updateProgress: updates.progress,
            features: menuSwitches.setting(.suggestions, isOn: settings.suggestions.isEnabled)
        )
    }

    /// The menu bar's three switches; only suggestions has a stored setting behind it, so the other two hold for this launch.
    private var menuSwitches = MenuBarFeatures()

    /// Carries out whatever the menu was asked for.
    private func carryOut(_ intent: MenuBarIntent) {
        switch intent {
        // Through the controller, which plays the cues and keeps one answer to what a control does.
        case .startDictation, .stopDictation:
            Task { [weak self] in await self?.controller?.toggleFromControl() }
        case .recover(let action):
            perform(action)
        case .insertRecent(let index):
            guard let recent = recents.entries[safe: index] else { return }
            // The app's own inserter: a fresh one would get the unannouncing pasteboard.
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
        case .setFeature(let feature, let isOn):
            menuSwitches = menuSwitches.setting(feature, isOn: isOn)
            if feature == .suggestions { apply(.toggle(.suggestionsEnabled, isOn: isOn)) }
            refreshMenuBar()
        case .quit:
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: Windows

    /// Opens whichever surface was asked for, so nothing else knows which class owns a window.
    private func show(_ destination: Destination) {
        switch destination {
        case .onboarding:
            // Not `presentOnboardingIfNeeded()`, which returns silently once the flow is finished.
            presentOnboarding(skippingWelcome: true)
        case .settings(let tab):
            settingsWindow.onClose = { [weak self] in self?.redrawMainWindow() }
            settingsWindow.show(tab, identity: signedInIdentity)
            // So the sidebar's Settings row lights up as the window appears.
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
            // A refusal describes one attempt, and describes nothing once the typing changes.
            wordRefusal = nil
            snippetRefusal = nil
            redrawMainWindow()
        }
        return window
    }

    /// Tells the updater what the app is in the middle of; the rule is ``UpdateGate``.
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

    /// Redraws from a fresh snapshot, reading everything on one hop so the pages agree.
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
            // The signed half only. See `Docs/entitlements.md`.
            knownEntitlement = account.profiles.load()?.entitlement
            // Read beside the entitlement, so two surfaces cannot draw from two readings.
            knownLocalAccount = account.local.load()
            await refreshPicture()
            await refreshPermissions()
            // A later refresh has newer state, and painting over it would leave the older reading up.
            guard reading == refreshGeneration else { return }
            mainWindow?.update(mainContent(measurements: measurements))
        }
    }

    private func mainContent(measurements: [StageMeasurement]) -> MainContent {
        let now = Date()
        // Handed over whole: `HistoryEntry` is `DictationRecord`, so nothing is rebuilt.
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
                    // The name macOS knows, read here so a test decides who is greeted.
                    systemName: NSFullUserName(),
                    shortcut: shortcut, settings: settings, now: now)),
            sidebar: SidebarPresenter.sidebar(
                for: SidebarSnapshot(
                    // The page the window shows; Settings is a window and lights nothing.
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

    /// What one page is filtered by, asked per page because every page is rebuilt on each redraw.
    private func query(for page: MainTab) -> String { queries[page] ?? "" }
    private func scope(for page: MainTab) -> String { scopes[page] ?? "" }
    /// What the dictation pipeline last reported. See where it is written.
    private var lastDictationState: DictationState = .idle
    private var snippetEditorIsOpen = false
    /// The same, for the word editor.
    private var wordEditorIsOpen = false
    /// Why the last Save was refused, per editor, until the next keystroke clears it.
    private var wordRefusal: String?
    private var snippetRefusal: String?

    /// Counts editor requests, so a slow one cannot open over a faster one that followed it.
    private var editorGeneration = 0
    /// The same for redraws, which suspend six times and so can land out of order.
    private var refreshGeneration = 0

    /// What the snippet editor currently says, or nothing when it is shut.
    private var snippetDraft: SnippetDraft? {
        snippetEditorIsOpen ? mainWindow?.snippetDraft : nil
    }

    /// What the word editor currently says, or nothing when it is shut.
    private var wordDraft: DictionaryDraft? {
        wordEditorIsOpen ? mainWindow?.wordDraft : nil
    }

    /// What the two stores held at the last refresh, cached because a page is built synchronously.
    private var knownWords: [DictionaryEntry] = []
    private var knownSnippets: [Snippet] = []
    private var knownEntitlement: Entitlement?
    /// The choice to work without an account, consulted only when there is no entitlement.
    private var knownLocalAccount: LocalAccount?
    /// The person's picture and the path it came from, kept together so it is fetched once per account.
    private var knownPicture: (path: String, bytes: Data)?
    /// The timings last read, so a keystroke redraws without hopping to the actor.
    private var lastMeasurements: [StageMeasurement] = []
    /// Everything the store keeps, which is not ``recents`` — that is the menu's five.
    private var kept: [DictationRecord] = []

    /// The last answer each gate gave; absent means unchecked, which the pages draw as silence.
    private var knownPermissions: [PermissionKind: PermissionStatus] = [:]

    /// Who is signed in, read from the cached profile so Settings knows even before the main window is drawn.
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

    /// The one switch every control in the main window passes through, internal so a test can drive it.
    func carryOut(_ intent: MainIntent) {
        switch intent {
        case .recover(let action): perform(action)
        case .go(let destination): show(destination)
        case .copy(let text): putOnClipboard(text, used: nil)
        case .insert(let text): insert(text, used: nil)
        case .show(let page):
            mainWindow?.show(page)
            // Redrawn from what was last read: nothing on disk changed by moving tabs.
            redrawMainWindow()
        case .change(let change): apply(change)

        case .forgetDictation(let id):
            let retention = Retention(days: settings.transcriptRetentionDays, now: Date())
            act { [weak self] in
                guard let self else { return }
                // Both files, or the words are still one shortcut away in the panel.
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
            // From the store, since `knownSnippets` can be a refresh behind.
            editorGeneration += 1
            let opening = editorGeneration
            Task { [weak self] in
                guard let self,
                    let snippet = await snippets.snippets().first(where: { $0.id == id }),
                    // Anything done while the disk was read wins over this.
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
            // Onboarding owns the whole sign-in conversation, so this asks for it explicitly.
            presentOnboarding(skippingWelcome: true, askingToSignIn: true)
        case .signOut:
            // Cleared first and the server told after, so signing out never waits on a network.
            account.profiles.clear()
            Task { [account] in await account.authentication.signOut() }
            refreshMainWindow()

        case .undoCorrection(let id):
            // In order: the history decides there was something to undo before the dictionary hears of it.
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

    /// Applies a setting through ``SettingsEditor``, so two screens cannot apply one choice two ways.
    private func apply(_ change: SettingsChange) {
        // A request to act now rather than a change, so there is no `Settings` to save.
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

    /// Runs a store change and redraws from what the store then holds, never from what it returned.
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

    /// Opens or closes the inline word editor, in both places that track it.
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

    /// Opens or closes the inline snippet editor in both places, so neither can disagree.
    private func editSnippet(_ draft: SnippetDraft?) {
        editorGeneration += 1
        snippetEditorIsOpen = draft != nil
        snippetRefusal = nil
        mainWindow?.editSnippet(draft)
        refreshMainWindow()
    }

    /// Saves a snippet, closing the editor only once it is in, as saving a word does.
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

    /// Follows a setting the user changed, and is the one place that acts on one.
    func settingsChanged(to updated: Settings) {
        let previous = settings
        settings = updated
        applyAppearance()
        applyLaunchAtLogin()

        // Acted on here, or the shortcut relabels itself and the old key keeps working.
        if updated.hotkey != previous.hotkey {
            startWatchingForTheShortcut()
        }
        if updated.hotkeyActivation != previous.hotkeyActivation {
            let activation = updated.hotkeyActivation
            Task { [weak self] in await self?.controller?.setActivation(activation) }
        }
        // As above: a switch that drew itself and changed nothing.
        if updated.installsUpdatesAutomatically != previous.installsUpdatesAutomatically {
            updates.setInstallsAutomatically(updated.installsUpdatesAutomatically)
        }
        // The master switch on the Suggestions screen is what builds and unbuilds the loop.
        if updated.suggestions != previous.suggestions {
            suggestionsChanged()
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

    /// Hides the main window while the user speaks, and deliberately does not bring it back.
    private func getOutOfTheWay(for state: DictationState) {
        guard settings.minimisesWhileDictating, case .recording = state else { return }
        mainWindow?.hide()
    }

    /// Draws every window Uttrflow owns light or dark together; `nil` means follow the Mac.
    private func applyAppearance() {
        NSApplication.shared.appearance =
            switch settings.appearance {
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            case .system: nil
            }
    }

    /// Tells macOS about starting at login, comparing first and reading the real state back after.
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
        // An informational notice asks nothing of the user, so it goes sooner.
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
            // A toggle, not a synthesised keypress with no release to close it.
            Task { [weak self] in await self?.controller?.toggleFromControl() }
        case .downloadSpeechModel:
            // Installing a model needs a window to show progress in. It has one now.
            show(.settings(.dictation))
        case .pasteManually:
            // Already on the clipboard, put there by the insertion floor before it reported failure.
            Task { await pipeline?.acknowledge() }
        case .showRecentDictations:
            // The clipboard is what failed, so this opens the menu, where Recent has the words.
            menuBar.openMenu()
        }
    }

    private func openSettingsPane(_ pane: SystemSettingsPane) async {
        switch pane {
        case .accessibility:
            let outcome = await AccessibilityPermissionGate().request()
            // A held modifier needs this grant to be watched at all. See `Docs/shortcuts.md`.
            if outcome == .granted, settings.hotkey.heldModifier != nil {
                startWatchingForTheShortcut()
            }
        case .microphone, .appleIntelligence:
            _ = await MicrophonePermissionGate().request()
        }
    }
}

// MARK: - The pipeline's seams, wired to the real stores

/// The correction engine over the user's dictionary: mapping only, deciding none of it.
private struct DictionaryCorrections: WordCorrecting {
    let dictionary: PersonalDictionaryStore
    let engine = WordCorrectionEngine()

    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async -> [DictationCorrection] {
        // No score, no judgement: Apple's recogniser reports none, so it gets no corrections.
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

/// Teaches the dictionary from a finished dictation, and is the only place the two targets meet.
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

/// A menu is built from a snapshot, so an index that has since gone must do nothing.
extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
