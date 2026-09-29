import Accessibility
import AppKit
import OSLog
import UttrflowAI
import UttrflowAccount
import UttrflowAudio
import UttrflowClipboard
import UttrflowContext
import UttrflowCore
import UttrflowDiagnostics
import UttrflowDictionary
import UttrflowHistory
import UttrflowInput
import UttrflowPermissions
import UttrflowPipeline
import UttrflowPredict
import UttrflowPredictCapture
import UttrflowPredictStore
import UttrflowSettings
import UttrflowSpeech
import UttrflowUX

/// Assembles the product and relays between it and the interface, deciding nothing itself.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// Records which of the three insertion routes a dictation took, which nothing else can tell.
    private nonisolated static let log = Logger(
        subsystem: "com.uttrflow.Uttrflow", category: "insertion")

    private let settingsStore = UserDefaultsSettingsStore()
    private var settings = Settings()
    /// The pipeline's recording cue, told when the sound setting changes.
    private var recordingSounds: RecordingSounds?

    private let menuBar = MenuBarController()
    private let dock = DockPanelController()
    private var recents = RecentDictations()
    /// The newest clips as the popover last read them, so a row's position finds the clip it shows.
    private var menuClips: [Clip] = []
    /// Where dictations are kept between launches, and the only thing that decides what is deleted.
    private let history: DictationHistoryStore
    /// Each dictation's audio, kept beside it only until its words land. See `Docs/recordings.md`.
    private let recordings: RecordingStore
    /// The user's own words, shared by all three parts of a dictation that read them.
    private let dictionary: PersonalDictionaryStore
    private let snippets: SnippetStore
    /// The account layer, made once and shared, because a second one signs with a different key.
    private let account: OnboardingAccountLayer
    /// Whether a renewal could be attempted, which only changes what the Account page says.
    private let network: any NetworkReachability = SystemNetworkReachability()
    /// What macOS is told about starting at login, held so a test can stand in for the system.
    private let loginItem: LaunchAtLogin
    /// Read before decoding and again for the tidier, shared so the second read is the warm one.
    private let context = MacContextEngine()
    /// Held, because the menu asks whether the model is ready every time it is drawn.
    private let modelStore = FileSystemSpeechModelStore.whisperKit()

    /// Crash and hang reports, sent only while the user has them switched on.
    private let crashReports = CrashReporter(
        info: Bundle.main.infoDictionary ?? [:], sdk: LiveCrashReportingSDK())
    /// Keeps the pipeline's stage timings for the session, which is what the diagnostics page reports on.
    private let diagnostics = DiagnosticsRecorder()
    /// Counts and timings, sent hourly unless Settings says not to. See `Docs/account-telemetry.md`.
    private var telemetry: UsageTelemetry?
    /// Whether secure keyboard entry is hiding the shortcut, checked on app switches and menu opens rather than on a timer.
    private let secureInput = SecureInputWatch()
    private var secureInputObserver: (any NSObjectProtocol)?

    /// Whether the recogniser can dictate, which is not whether its files are on disk.
    private var speechReadiness: SpeechModelReadiness = .notInstalled
    /// When the load under way began, so the estimate is said only once a load has run long enough to need it.
    private var speechLoadStarted: ContinuousClock.Instant?
    /// Redraws the load's estimate once a second while a load runs, and is gone once it ends.
    private var speechLoadTicker: Task<Void, Never>?
    /// The recogniser the pipeline transcribes with, which Diagnostics names rather than the setting.
    private var speechInUse: SpeechEngineKind?
    /// Whether the last load already failed, so a second failure offers a download rather than another reload.
    private var speechLoadFailedBefore = false

    /// What the model is when it cannot be loaded from disk: never downloaded, or downloaded only in part.
    private var speechModelAbsence: SpeechModelReadiness {
        modelStore.isIncomplete(.default) ? .incomplete : .notInstalled
    }

    /// The load as every dictation surface tells it, read from ``speechReadiness`` and nothing else.
    private var speechModelLoad: SpeechModelLoad? {
        speechReadiness.load(since: speechLoadStarted, now: ContinuousClock.now)
    }

    /// How the recording in progress is going against ``DictationLimit``.
    private var recordingAdvice: DictationAdvice = .keepGoing
    /// What the dock has to say to end a recording that is under way right now.
    private var recordingStopGesture: StopGesture = .letGo

    private var pipeline: DictationPipeline?
    /// The pipeline's recogniser, held so memory pressure can let it go between dictations.
    private var speechEngine: BackedSpeechEngine?
    private var controller: DictationController<ContinuousClock>?
    private var stateTask: Task<Void, Never>?
    private var dismissalTask: Task<Void, Never>?

    // MARK: The clipboard

    private let clipboard: ClipboardStore

    /// Where every local store lives, kept because tab-to-complete opens its corpus after launch.
    private let container: URL

    /// Tab-to-complete, built only where the user has asked for it. See `Docs/predict.md`.
    private var completions: SuggestionCoordinator?

    /// The local model that validates each suggestion, handed in by the entry point so tests link no MLX.
    private let scoring: (any CandidateScoring)?
    /// The local model that invents a suggestion where the corpus has none, handed in the same way.
    private let generating: (any CandidateGenerating)?
    /// Fetches and loads that model's weights, reporting progress, run when tab-to-complete is first built.
    private let prepareModel: (@Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void)?
    /// Frees that model's weights, run when tab-to-complete is turned off.
    private let releaseModel: (@Sendable () async -> Void)?
    /// Asks which clean-up engines can run, held as a seam so availability changes are testable.
    private let transformerReadiness: @Sendable (UserProfile) async -> Set<TransformerKind>
    /// Whether the weights have been asked for and not let go since, so turning the feature on twice does not ask twice.
    private var isModelPreparing = false
    /// Counts each ask and each release, so a load that lands after the feature was turned off reports nothing.
    private var modelAsk = 0
    /// The latest fetch of those weights, internal so a test can wait for it rather than for the clock.
    private(set) var modelPreparation: Task<Void, Never>?
    /// When the suggestion model gives memory back and takes it again; internal so a test can shorten the waits.
    var memoryPressure = SuggestionModelPressure()
    /// The reload waiting for memory to stay calm, cancelled by the next reading; internal so a test can wait for it.
    private(set) var pressureReload: Task<Void, Never>?
    private let pressureSource = MemoryPressureSource()
    /// Which clean-up engines answered that they could run; internal so a test can read it back.
    private(set) var transformerAvailability: [TransformerKind: Bool] = [:]
    /// Prevents a slower earlier probe from replacing a newer reading.
    private var transformerProbeGeneration = 0
    /// The clean-up engine that produced the last inserted dictation.
    private(set) var lastCleanedBy: TransformerKind?
    /// What the store last said about the speech model on disk; internal so a test can read it.
    private(set) var speechModelPresence: DiagnosticsModelPresence?
    /// The built-in recogniser's locale asset inventory answer.
    private(set) var appleSpeechStatus: DiagnosticsAppleSpeechStatus?
    /// The built-in recogniser's last typed model-load failure.
    private(set) var appleSpeechLoadFailure: SpeechEngineError?

    /// How far along that fetch is; internal so a test can read back what it did.
    private(set) var suggestionModel: SuggestionModelReadiness = .notAsked {
        didSet {
            guard suggestionModel != oldValue else { return }
            settingsPage.setSuggestionModel(suggestionModel)
            refreshMenuBar()
        }
    }
    private var suggestionSecureInputNotice: String?

    /// Builds the app around one folder, which a test points at a temporary one.
    init(
        container: URL = .applicationSupportDirectory, loginItem: LaunchAtLogin = LaunchAtLogin(),
        account: OnboardingAccountLayer = .forThisBuild(),
        scoring: (any CandidateScoring)? = nil, generating: (any CandidateGenerating)? = nil,
        prepareModel: (@Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void)? = nil,
        releaseModel: (@Sendable () async -> Void)? = nil,
        transformerReadiness: @escaping @Sendable (UserProfile) async -> Set<TransformerKind> = {
            profile in await SettingsCapabilities.refreshed(for: profile).readyTransformers
        }
    ) {
        self.container = container
        self.loginItem = loginItem
        self.account = account
        self.scoring = scoring
        self.generating = generating
        self.prepareModel = prepareModel
        self.releaseModel = releaseModel
        self.transformerReadiness = transformerReadiness
        history = DictationHistoryStore(file: DictationHistoryStore.defaultFile(in: container))
        recordings = RecordingStore(directory: RecordingStore.defaultDirectory(in: container))
        dictionary = PersonalDictionaryStore(
            file: PersonalDictionaryStore.defaultFile(in: container))
        snippets = SnippetStore(file: SnippetStore.defaultFile(in: container))
        clipboard = ClipboardStore(file: ClipboardStore.defaultFile(in: container))
        super.init()
    }
    private let clipboardWatcher = PasteboardWatcher(source: SystemClipboardSource())
    private let quickPanel = QuickPanelController()

    /// Keeping the app up to date, asking this delegate what it is doing rather than being told.
    lazy var updates = UpdateController { [weak self] in
        // No delegate means no idea, and no idea means do not interrupt.
        self?.updateActivity ?? UpdateActivity(isDictating: true)
    }
    /// One registration per claimed shortcut, because each one registers a single key.
    private var claimedHotkeys: [ShortcutAction: CarbonHotkeyMonitor] = [:]
    /// The claimed shortcuts registered now; internal so a test can see none are held while signed out.
    var armedShortcuts: Set<ShortcutAction> { Set(claimedHotkeys.keys) }
    /// Whether the clipboard panel is open, so a test can see a refused shortcut left it shut.
    var isQuickPanelOpen: Bool { quickPanel.isVisible }
    /// Whether the floating button is on screen, so a test can see a sign-out took it away.
    var isFloatingButtonShown: Bool { dock.isVisible }
    /// Whether copies are being recorded, so a test can see a sign-out stopped it.
    var isWatchingTheClipboard: Bool { clipboardWatchTask != nil }
    private var claimedTasks: [ShortcutAction: Task<Void, Never>] = [:]
    /// The last thing dictated, so it can be put back without reopening History.
    private(set) var lastTranscript: String?
    /// The history record the last transcript came from, so deleting that record forgets it too.
    private(set) var lastTranscriptID: UUID?
    /// Asked when the panel opens whether a paste can be placed, held so the answer costs one call.
    private let accessibility = AccessibilityPermissionGate()
    private let microphone = MicrophonePermissionGate()
    private let focus: any AccessibilityFocus = AXAccessibilityFocus()
    /// D5 — asked, when the panel opens, which languages have a formatter on this disk.
    private let formatter: any CodeFormatting = SystemCodeFormatter()

    /// The one pasteboard that announces its writes, so no inserter can silently forget to. See `Docs/insertion.md`.
    private lazy var announcingPasteboard = SystemPasteboard(
        willWrite: { [clipboardWatcher] in clipboardWatcher.ignoreNextWrite(of: $0) },
        willWritePicture: { [clipboardWatcher] in clipboardWatcher.ignoreNextPicture($0) })

    /// Puts a chosen clip where the caret is, announcing the write so it is not read as a copy.
    private lazy var clipInserter = TextInsertion.coordinator(
        pasteboard: announcingPasteboard)

    /// The same for a secret clip, whose words reach the clipboard only with the concealed marker.
    private lazy var secretInserter = TextInsertion.coordinator(
        pasteboard: ConcealingPasteboard(announcingPasteboard))

    /// The panel's state while it is open, held here because a window has no memory.
    private var panel: PanelSnapshot?
    private var panelTarget: InsertionDestination?
    /// Counts Format presses, so only the latest run's result may open its sheet.
    private var formatterRuns = 0
    /// Counts the store reads the panel has asked for, so an older list never replaces a newer one.
    private var panelReads = 0
    private var clipboardWatchTask: Task<Void, Never>?

    /// F7, F9 — the clip a delete removed, held by the app because the undo outlives the panel.
    private var undoOffer = PanelUndoOffer()
    private var undoTask: Task<Void, Never>?
    private let noticeLinger = NoticeLinger()
    /// Puts the floating button back once a panel paste's report has been read.
    private var pasteReportTask: Task<Void, Never>?
    /// What the idle floating button shows while a panel paste's report lingers.
    private var pasteReport: DockPresentation?
    /// The editor opening against the disk, kept so a caller can wait for it rather than poll for it.
    private(set) var openingEditor: Task<Void, Never>?
    /// The store work the last main-window intent set going, so a test awaits it rather than a clock.
    private(set) var intentWork: Task<Void, Never>?
    /// The last sweep of expired recordings and transcripts, so a test awaits it rather than a clock.
    private(set) var sweeping: Task<Void, Never>?
    /// A3, A7 — where the user was when the panel closed, while reopening still counts as undoing.
    private var resume: PanelResume?
    /// Long enough to reach for the keyboard, short enough to not undo a forgotten delete.
    private static let undoWindow = Duration.seconds(8)

    /// Internal so a test can install one and read back what an intent opened it on.
    var mainWindow: MainWindowController?
    /// The Settings page over *this* app's stores, never a second set of actors on the same files.
    private lazy var settingsPage = SettingsPageController(
        store: settingsStore,
        personalisation: Self.personalisation(
            in: container, dictionary: dictionary, history: history, clipboard: clipboard,
            elsewhere: keptElsewhere(), running: { [weak self] in self?.completions }),
        onChange: { [weak self] settings in self?.settingsChanged(to: settings) },
        // Through the same switch the main window uses, so one choice is never applied two ways.
        onRequest: { [weak self] change in self?.apply(change) },
        onReset: { [weak self] reset in self?.forget(after: reset) },
        onShortcutRecording: { [weak self] isRecording in
            self?.shortcutRecordingChanged(to: isRecording)
        })
    private var onboarding: OnboardingWindowController?
    /// The speech model's one download, which every onboarding window joins and closing one does not stop.
    private lazy var speechInstall: SharedModelInstall = {
        let install = SharedModelInstall(wrapping: SpeechModelInstall(store: modelStore, model: .default))
        install.onProgress = { [weak self] in self?.speechModelDownloaded($0) }
        install.onEnd = { [weak self] _ in self?.speechModelDownloadEnded() }
        return install
    }()
    /// What is typed into each page's search field, kept per page because six of them have one.
    private var queries: [MainTab: String] = [:]
    private var scopes: [MainTab: String] = [:]

    /// How long a finished result stays up, so the last dictation does not sit over every app.
    static let successLingers = Duration.seconds(2)
    /// Longer, because a failure asks something of the user — but it still goes.
    static let failureLingers = Duration.seconds(10)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before the first read, so an install onboarded under ⌥Space keeps it. See `Docs/shortcuts.md`.
        settingsStore.pinDefaults(onboarded: UserDefaultsOnboardingRecordStore().hasFinished)
        settings = settingsStore.load()
        // Reconciled at launch too: the login item can be removed without telling the app.
        applyAppearance()
        _ = BrandFont.isAvailable
        InstalledApplicationName.install()
        applyLaunchAtLogin()
        startTelemetry()
        crashReports.follow(isEnabled: settings.sendsCrashReports)
        buildPipeline()
        seedTheDictionary()
        sweepExpired()
        wireInterface()
        CGEventKeystrokeSender.startObservingLayout()
        startWatchingForTheShortcut()
        startWatchingTheClipboard()
        startCompletingWhatIsTyped()
        pressureSource.start { [weak self] in self?.memoryPressureChanged(to: $0) }
        loadSpeechModel()
        probeTransformers()
        probeSpeechModel()
        probeAppleSpeechAssets()
        refreshAccount()
        // A Mac that worked without an account keeps no trace of it, and meets sign-in like anyone signed out.
        RetiredLocalAccount.forget()
        // Everything above armed itself only with a session; this records which state that was.
        appliedSession = isSignedIn
        refreshMenuBar()
        presentOnboardingIfNeeded()
        // Shown at launch, since a menu-bar icon alone is an interface most people never find.
        if onboarding == nil {
            show(.main(.home))
        } else {
            refreshMainWindow()
        }
        // Configured last, from the setting; the automatic check itself waits for `modelLoadingSettled()`.
        updates.onProgressChanged = { [weak self] in self?.refreshMenuBar() }
        updates.begin(automatically: settings.installsUpdatesAutomatically)
    }

    /// Builds the telemetry service from the saved switch and starts its hourly flush.
    private func startTelemetry() {
        let usage = UsageTelemetry(
            isEnabled: settings.sharesUsageStatistics, sender: account.telemetry,
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        usage.start()
        telemetry = usage
    }

    /// Deletes recordings and transcripts past their retention, with or without a window. See `Docs/recordings.md`.
    func sweepExpired(now: Date = Date()) {
        let retention = Retention(days: settings.transcriptRetentionDays, now: now)
        let previous = sweeping
        sweeping = Task { [recordings, history] in
            await previous?.value
            _ = await recordings.waiting(now: now)
            _ = await history.records(keeping: retention)
        }
    }

    /// Writes the words this build ships knowing, which happens once and never blocks the launch.
    private func seedTheDictionary() {
        Task { [dictionary] in
            do {
                try await dictionary.seedShippedWords(at: Date())
            } catch {
                Self.log.error(
                    "dictionary seeding failed: \(SuggestionLog.failure(error), privacy: .public)")
            }
        }
    }

    /// Everything Settings can count and forget, over the stores this app opens in this container.
    nonisolated static func personalisation(
        in container: URL, dictionary: PersonalDictionaryStore, history: DictationHistoryStore,
        clipboard: ClipboardStore, elsewhere: KeptElsewhere = KeptElsewhere(),
        running: @escaping @Sendable @MainActor () -> SuggestionCoordinator? = { nil }
    ) -> FilePersonalisationStore {
        FilePersonalisationStore(
            dictionary: dictionary, history: history, clipboard: clipboard,
            suggestions: PredictCorpus(container: container, running: running),
            met: { AppDelegate.applicationsTheLoopHasMet(in: container) },
            elsewhere: elsewhere)
    }

    /// Applications the completion loop has met, so the Suggestions list can offer a switch for each.
    nonisolated static func applicationsTheLoopHasMet(in container: URL) -> Set<String> {
        let file = CapturePreferencesFile(
            path: CapturePreferencesFile.defaultFile(in: container).path(percentEncoded: false))
        return Set(file.load().consent.keys)
    }

    /// The files a full reset reaches that the settings module has no store for.
    private func keptElsewhere() -> KeptElsewhere {
        KeptElsewhere(
            recordings: { [recordings] in try await recordings.discardEverything() },
            snippets: { [snippets] in try await snippets.deleteEverything() },
            suggestionConsent: { [weak self] in try await self?.forgetEveryConsentAnswer() })
    }

    /// Forgets which applications completions may learn from, through the running loop when there is one.
    private func forgetEveryConsentAnswer() async throws {
        if let completions {
            try await completions.forgetEveryAnswer()
            return
        }
        try CapturePreferencesFile(
            path: CapturePreferencesFile.defaultFile(in: container).path(percentEncoded: false)
        ).remove()
    }

    /// Deletes a model that is on disk but will not load, and opens setup to download it again.
    private func repairSpeechModel() {
        try? modelStore.remove(.default)
        speechReadiness = .notInstalled
        speechLoadFailedBefore = false
        probeSpeechModel()
        refreshSpeechModelSurfaces()
        show(.onboarding)
    }

    /// Loads a model that setup has just installed, so dictation works without a relaunch.
    private func loadSpeechModelIfItArrived() {
        switch speechReadiness {
        case .notInstalled, .incomplete, .loadFailed: loadSpeechModel()
        case .ready, .downloading, .loading, .loadFailedAgain: return
        }
    }

    /// Shows the download everywhere a person might try to dictate, redrawing once per whole percent.
    private func speechModelDownloaded(_ fraction: Double) {
        guard speechReadiness != .ready, speechReadiness != .loading else { return }
        let shown = speechReadiness
        speechReadiness = .downloading(fractionCompleted: fraction)
        if case .downloading(let before?) = shown,
            MenuBarPresenter.percentage(of: before) == MenuBarPresenter.percentage(of: fraction)
        {
            return
        }
        refreshSpeechModelSurfaces()
    }

    /// Loads the model once its download ends, whether or not a window is still showing it.
    private func speechModelDownloadEnded() {
        if case .downloading = speechReadiness { speechReadiness = speechModelAbsence }
        // New files deserve a reload before they are called broken.
        speechLoadFailedBefore = false
        probeSpeechModel()
        loadSpeechModelIfItArrived()
        refreshSpeechModelSurfaces()
    }

    /// Loads the recogniser, saying so until it can dictate. See `Docs/startup.md`.
    private func loadSpeechModel(
        by load: @escaping @MainActor (DictationPipeline) async -> Void = { await $0.prepare() }
    ) {
        guard modelStore.isInstalled(.default) else {
            speechReadiness = speechModelAbsence
            // Nothing to load, so nothing for an automatic update check to compete with.
            updates.modelLoadingSettled()
            return
        }
        speechReadiness = .loading
        speechLoadStarted = .now
        refreshSpeechModelSurfaces()
        // Silent through the first seconds a warm load needs, then a redraw a second until the load ends.
        speechLoadTicker?.cancel()
        speechLoadTicker = Task { [weak self] in
            try? await Task.sleep(for: SpeechModelLoad.estimateAfter)
            while !Task.isCancelled {
                guard let self, speechReadiness == .loading else { return }
                refreshSpeechModelEstimate()
                try? await Task.sleep(for: SpeechModelLoadEstimate.redrawInterval)
            }
        }
        Task { [weak self] in
            guard let pipeline = self?.pipeline else { return }
            await load(pipeline)
            guard let self else { return }
            speechInUse = await pipeline.speechKind
            speechReadiness = settle(isReady: await pipeline.isReady)
            speechLoadTicker?.cancel()
            speechLoadTicker = nil
            refreshSpeechModelSurfaces()
            // The load ended, one way or another; an automatic update check may now start.
            updates.modelLoadingSettled()
        }
    }

    /// Where a load that has ended leaves the model: ready, missing files, or failed once or twice.
    private func settle(isReady: Bool) -> SpeechModelReadiness {
        let isInstalled = modelStore.isInstalled(.default)
        let afterLoad = SpeechModelReadiness.afterLoad(isReady: isReady, isInstalled: isInstalled)
        let settled: SpeechModelReadiness
        switch afterLoad {
        case .ready: settled = .ready
        case .loadFailed: settled = speechLoadFailedBefore ? .loadFailedAgain : .loadFailed
        case .notInstalled:
            settled = modelStore.isIncomplete(.default) ? .incomplete : .notInstalled
        case .downloading, .loading, .loadFailedAgain, .incomplete: settled = afterLoad
        }
        switch settled {
        case .ready: speechLoadFailedBefore = false
        case .loadFailed, .loadFailedAgain: speechLoadFailedBefore = true
        case .downloading, .loading, .incomplete, .notInstalled: break
        }
        return settled
    }

    /// Redraws everywhere a person might try to dictate, from the load as it stands.
    private func refreshSpeechModelSurfaces() {
        refreshSpeechModelEstimate()
        // Guarded here, since the redraw also wakes the updater, which launch starts last on purpose.
        if mainWindow != nil { redrawMainWindow() }
    }

    /// Moves the estimate on in the menu bar and the floating button; home's hero moves its own.
    private func refreshSpeechModelEstimate() {
        refreshMenuBar()
        dock.update(with: dockPresentation(for: lastDictationState))
    }

    /// The floating button for a state, with the speech model's load drawn in.
    private func dockPresentation(for state: DictationState) -> DockPresentation {
        if case .idle = state, let pasteReport { return pasteReport }
        return DictationPresenter.dock(
            for: state, advice: recordingAdvice, speechModel: speechModelLoad,
            download: speechReadiness.download, stopGesture: recordingStopGesture)
    }

    /// Asks each clean-up engine whether it could run, so Diagnostics has an answer to show; the task ends once it has.
    @discardableResult
    func probeTransformers() -> Task<Void, Never> {
        transformerProbeGeneration += 1
        let generation = transformerProbeGeneration
        return Task { [weak self] in
            guard let self else { return }
            let ready = await transformerReadiness(settings.profile)
            guard generation == transformerProbeGeneration else { return }
            transformerAvailability = Dictionary(
                uniqueKeysWithValues: TransformerKind.allCases.map { ($0, ready.contains($0)) })
            refreshMainWindow()
        }
    }

    /// Reads the speech model's files off the main actor, so Diagnostics can say whether it is there.
    @discardableResult
    func probeSpeechModel() -> Task<Void, Never> {
        let store = modelStore
        return Task { [weak self] in
            let presence = await Task.detached(priority: .utility) {
                let model = SpeechModel.default
                let installed = store.isInstalled(model)
                return DiagnosticsModelPresence(
                    isInstalled: installed, bytesOnDisk: installed ? store.bytesOnDisk(model) : nil,
                    isMultilingual: model.isMultilingual)
            }.value
            guard let self else { return }
            speechModelPresence = presence
            refreshMainWindow()
        }
    }

    /// Reads the system recogniser's asset inventory for the locale its backend loads.
    @discardableResult
    func probeAppleSpeechAssets() -> Task<Void, Never> {
        Task { [weak self] in
            let status = await AppleSpeechBackend.assetStatus()
            guard let self else { return }
            appleSpeechStatus =
                switch status {
                case .installed: .installed
                case .needsDownload: .needsDownload
                case .downloading: .downloading
                case .unsupported: .unsupported
                }
            refreshMainWindow()
        }
    }

    /// What the menu bar shows now, internal so a test can read what the app drew.
    var menuBarPresentation: MenuBarPresentation { menuBar.presentation }

    /// Redraws the menu bar from whatever the app currently knows.
    private func refreshMenuBar() {
        let signedIn = isSignedIn
        menuBar.requiresSignIn = !signedIn
        menuBar.update(
            with: signedIn
                ? MenuBarPresenter.present(menuBarState(for: lastDictationState)) : SessionGate.signedOutMenu)
    }

    /// Re-reads the account in the background at launch; internal so a test can await it. See `Docs/entitlements.md`.
    @discardableResult
    func refreshAccount() -> Task<Void, Never> {
        Task { [account] in
            let outcome = await account.refresh.run()
            // Only a change is worth a redraw; `unchanged` is the common answer.
            guard outcome == .updated || outcome == .signedOut else { return }
            // A session the server ended is a sign-out, closed the same way.
            followSession()
            refreshMainWindow()
        }
    }

    // MARK: The session

    /// Whether a backend session is on this Mac; every surface but sign-in waits on it. See `Docs/entitlements.md`.
    var isSignedIn: Bool {
        SessionGate.isSignedIn(
            EntitlementGate(profiles: account.profiles)
                .access(at: Date(), networkIsReachable: network.isReachable))
    }

    /// What runs in the background now, decided from the session and the settings together.
    var surfaces: SessionSurfaces { SessionSurfaces(isSignedIn: isSignedIn, settings: settings) }

    /// The session the surfaces were last opened or closed for, so a repeat changes nothing.
    private var appliedSession: Bool?

    /// Opens every surface for a new session or closes them all for a lost one; internal so a test can drive it.
    func followSession() {
        let signedIn = isSignedIn
        guard signedIn != appliedSession else { return refreshMenuBar() }
        appliedSession = signedIn
        if signedIn { openForSession() } else { closeForSignedOut() }
    }

    /// Arms the shortcuts, the clipboard, tab-to-complete and the floating button a sign-in makes available.
    private func openForSession() {
        startWatchingForTheShortcut()
        startWatchingForClaimedShortcuts()
        followTheClipboardSwitch()
        startCompletingWhatIsTyped()
        showTheFloatingButtonIfWanted()
        refreshMenuBar()
    }

    /// Closes every window and panel, stops listening, and leaves sign-in as the one thing on screen.
    private func closeForSignedOut() {
        startWatchingForTheShortcut()
        startWatchingForClaimedShortcuts()
        followTheClipboardSwitch()
        stopCompleting()
        showTheFloatingButtonIfWanted()
        if quickPanel.isVisible { closeQuickPanel() }
        mainWindow?.close()
        mainWindow = nil
        refreshMenuBar()
        // An open flow may be past sign-in, on a page only a session may see.
        onboarding?.signedOut()
        show(.onboarding)
    }

    /// Starts or ends a dictation from a control, and does nothing while signed out.
    private func toggleDictation() {
        guard isSignedIn else { return }
        // Through the controller, which plays the cues and keeps one answer to what a control does.
        Task { [weak self] in await self?.controller?.toggleFromControl() }
    }

    /// Clicking the Dock icon or reopening from Finder, which brings back a main window that is not on screen.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows: Bool
    ) -> Bool {
        if Reopening.showsMainWindow(
            mainWindowIsVisible: mainWindow?.isVisible == true,
            onboardingIsVisible: onboarding?.isVisible == true)
        {
            show(.main(.home))
        }
        return true
    }

    // MARK: The menu bar at the top of the screen

    @objc func showMainWindowFromMenu(_ sender: Any?) { show(.main(.home)) }
    @objc func showSettingsFromMenu(_ sender: Any?) { show(.settings(.general)) }
    @objc func showDiagnosticsFromMenu(_ sender: Any?) { show(.settings(.diagnostics)) }

    /// Shows or hides the sidebar's names, and does nothing when there is no window yet.
    @objc func toggleSidebarFromMenu(_ sender: Any?) { mainWindow?.toggleSidebar() }

    /// Puts the caret in the page's search field, or opens Home's search, as ⌘K does, when the page has none.
    @objc func findFromMenu(_ sender: Any?) {
        guard let mainWindow, mainWindow.isVisible else { return }
        if mainWindow.canFocusSearch {
            mainWindow.focusSearch()
        } else {
            carryOut(.search)
        }
    }

    /// Answers for the two items whose state the window decides, rather than the menu's fixed text.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleSidebarFromMenu(_:)):
            // Named after what choosing it does, which a fixed title gets wrong half the time.
            item.title = mainWindow?.isSidebarExpanded == true ? "Hide Sidebar" : "Show Sidebar"
            return mainWindow != nil
        case #selector(findFromMenu(_:)):
            return mainWindow?.isVisible == true
        default:
            return true
        }
    }

    /// Shows the first-run flow when setup is unfinished or nobody is signed in.
    private func presentOnboardingIfNeeded() {
        guard
            !isSignedIn
                || OnboardingWindowController(
                    settingsStore: settingsStore, installer: speechInstall, account: account
                ).isRequired
        else { return }
        presentOnboarding()
    }

    /// Brings forward the flow already open, else builds a fresh one so a finished flow never reopens on its last page.
    private func presentOnboarding() {
        let (onboarding, isNew) = OnboardingWindowController.reusing(onboarding) {
            OnboardingWindowController(
                settingsStore: settingsStore, installer: speechInstall, account: account)
        }
        guard isNew else {
            onboarding.present()
            return
        }
        self.onboarding = onboarding
        // The rest of the app opens as soon as the session exists, before the setup pages after it.
        onboarding.onSignIn = { [weak self] in self?.followSession() }
        onboarding.onFinish = { [weak self] _ in
            guard let self else { return }
            // Re-read, because the microphone check writes the language list through the same store.
            settingsChanged(to: settingsStore.load())
            self.onboarding = nil
            updates.refresh()
            // The session is what onboarding changes that the settings store knows nothing about.
            refreshMainWindow()
            // The last page promises the dashboard, so finishing opens it.
            show(.main(.home))
        }
        // However the window goes, including the red button, which changes the Account page.
        onboarding.onClose = { [weak self, weak onboarding] in
            guard let self else { return }
            // Cleared here too, so a window shut with the red button no longer holds updates back.
            if self.onboarding === onboarding { self.onboarding = nil }
            updates.refresh()
            refreshMainWindow()
            loadSpeechModelIfItArrived()
        }
        onboarding.present()
    }

    /// How long quitting waits for a dictation to land. See `Docs/quitting.md`.
    private static let quitBudget = Duration.seconds(15)

    /// Finishes the dictation in flight before letting the process die, but not for ever.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        completions?.stop()
        Task { [weak self, pipeline, clipboard, telemetry] in
            let controller = self?.controller
            let finishingCompletions = self?.completions
            let quittingPipeline = pipeline.map { pipeline in
                AppQuitCoordinator.Pipeline(
                    currentState: { await pipeline.currentState },
                    finishRecording: { await pipeline.finishRecording() },
                    states: { await pipeline.states() })
            }
            await AppQuitCoordinator.finish(
                budget: Self.quitBudget,
                clock: ContinuousClock(),
                pipeline: quittingPipeline,
                flushClipboard: { await clipboard.flushUse() },
                finishCompletions: { await finishingCompletions?.finishWrites() },
                stopController: { await controller?.stop() },
                reply: {
                    // After the dictation has landed, so a quit's last report never holds one up.
                    await telemetry?.flushBeforeQuitting()
                    // On every path: an unanswered `terminateLater` is an app that cannot be quit.
                    await MainActor.run {
                        NSApplication.shared.reply(toApplicationShouldTerminate: true)
                    }
                })
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        stateTask?.cancel()
        dismissalTask?.cancel()
        completions?.stop()
        pressureSource.stop()
    }

    /// Builds tab-to-complete, or leaves it unbuilt, which is what everybody who has not asked for it gets.
    private func startCompletingWhatIsTyped() {
        guard surfaces.completesWhatIsTyped, completions == nil else { return }
        prepareTheModelIfNeeded()
        do {
            let coordinator = try SuggestionCoordinator(
                container: container, preferences: settings.suggestions, scoring: scoring,
                generating: generating)
            // ⌥⎋ persists the master switch off, so the screen agrees and turning it back on rebuilds the loop.
            coordinator.onTurnedOffEverywhere = { [weak self] in
                self?.apply(.toggle(.suggestionsEnabled, isOn: false))
            }
            coordinator.onSecureInputBlockingChanged = { [weak self] isBlocking in
                self?.suggestionSecureInputNotice = isBlocking ? SecureInputWatch.suggestionNotice : nil
                self?.refreshMenuBar()
            }
            completions = coordinator
            coordinator.start()
        } catch {
            Self.log.error("the corpus would not open: \(SuggestionLog.failure(error), privacy: .public)")
        }
    }

    /// Fetches the several gigabytes of weights once somebody has asked for the feature, saying how far along.
    private func prepareTheModelIfNeeded() {
        guard let prepareModel, !isModelPreparing else { return }
        isModelPreparing = true
        suggestionModel = .downloading(fractionCompleted: nil)
        // Built here rather than inside the task, so it takes its own handle and not the task's.
        let report: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in self?.suggestionModelProgressed(fraction) }
        }
        modelAsk += 1
        let ask = modelAsk
        let previous = modelPreparation
        modelPreparation = Task { [weak self] in
            // After the release before it, so a quick off and on never frees the weights it just loaded.
            await previous?.value
            do {
                try await prepareModel(report)
                guard self?.modelAsk == ask else { return }
                self?.suggestionModel = .ready
            } catch {
                Self.log.error(
                    "the suggestion model did not load: \(SuggestionLog.failure(error), privacy: .public)")
                guard self?.modelAsk == ask else { return }
                // Cleared, so turning the feature off and on tries again rather than staying dead all launch.
                self?.isModelPreparing = false
                self?.suggestionModel = .failed
            }
        }
    }

    /// Says the weights must be fetched again, after a reload found them gone from disk and did not fetch them itself.
    func suggestionModelWentMissing() {
        guard settings.suggestions.isEnabled, isModelPreparing else { return }
        // Cleared, so turning the switch off and on fetches them, as it does after any failed fetch.
        isModelPreparing = false
        suggestionModel = .failed
    }

    /// Lets the weights go once the feature is off, stopping any load still in flight. See `Docs/performance.md`.
    private func releaseTheModel() {
        guard isModelPreparing || suggestionModel == .failed else { return }
        isModelPreparing = false
        modelAsk += 1
        suggestionModel = .notAsked
        let previous = modelPreparation
        let releaseModel = releaseModel
        // A load still in flight is stopped rather than waited out, so no download or read runs on after the release.
        previous?.cancel()
        modelPreparation = Task {
            await previous?.value
            await releaseModel?()
        }
    }

    /// Lets the recogniser go under memory pressure unless a dictation is under way; the next key-down loads it again.
    private func releaseSpeechModelIfIdle() {
        guard case .idle = lastDictationState, let speechEngine else { return }
        Task { await speechEngine.release() }
    }

    /// Releases the suggestion model when memory is pressed, and loads it again once calm has lasted. See `Docs/performance.md`.
    func memoryPressureChanged(to level: MemoryPressureLevel) {
        switch level {
        case .warning, .critical:
            pressureReload?.cancel()
            pressureReload = nil
            releaseSpeechModelIfIdle()
            guard settings.suggestions.isEnabled, isModelPreparing else { return }
            memoryPressure.released(at: .now)
            releaseTheModel()
            suggestionModel = .releasedForMemory
        case .normal:
            // A repeated calm keeps the countdown already running.
            guard memoryPressure.isReleased, pressureReload == nil else { return }
            let wait = memoryPressure.wait
            pressureReload = Task { [weak self] in
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled, let self, memoryPressure.isReleased,
                    settings.suggestions.isEnabled
                else { return }
                memoryPressure.reloaded(at: .now)
                prepareTheModelIfNeeded()
            }
        }
    }

    /// Shows the model as getting ready while an idle reload runs, then as ready or failed by how it ends.
    func suggestionModelReloaded(_ event: IdleReload) {
        guard isModelPreparing else { return }
        switch event {
        case .started where suggestionModel == .ready:
            suggestionModel = .loading
        case .finished where suggestionModel == .loading:
            suggestionModel = .ready
        case .failed where suggestionModel == .loading:
            // Cleared so that turning the feature off and on loads the model again.
            isModelPreparing = false
            suggestionModel = .failed
        case .started, .finished, .failed:
            break
        }
    }

    /// Moves the reading on, and to loading once every byte is down and only the reading-in is left.
    private func suggestionModelProgressed(_ fraction: Double) {
        guard case .downloading = suggestionModel else { return }
        suggestionModel = fraction >= 1 ? .loading : .downloading(fractionCompleted: fraction)
    }

    /// Follows the Suggestions screen: builds the loop, takes it away, or hands it what changed.
    private func suggestionsChanged() {
        guard settings.suggestions.isEnabled else { return stopCompleting() }
        guard let completions else { return startCompletingWhatIsTyped() }
        completions.follow(settings.suggestions)
    }

    /// Takes tab-to-complete away and lets its model go.
    private func stopCompleting() {
        completions?.stop()
        completions = nil
        memoryPressure.forget()
        pressureReload?.cancel()
        pressureReload = nil
        releaseTheModel()
    }

    /// Arms the shortcut again when it could not be armed before. See `Docs/shortcuts.md`.
    func applicationDidBecomeActive(_ notification: Notification) {
        probeTransformers()
        // Whatever held the combination may have quit while the user was away.
        if !unarmedShortcuts.isEmpty { startWatchingForClaimedShortcuts() }
        guard shortcutArming.failure != nil else { return }
        startWatchingForTheShortcut()
    }

    // MARK: Assembly

    /// The tidier for these settings, built here alone so no caller can leave the dictionary out of it.
    private func cleaner(for settings: Settings) -> TransformerRouter {
        TextTransformers.router(
            configuration: settings.engines, steps: settings.cleaning,
            spellings: { [dictionary] in await dictionary.index() })
    }

    /// The recogniser of `kind`, over the downloaded model.
    private func makeSpeechEngine(_ kind: SpeechEngineKind) -> any SpeechEngine {
        let model = SpeechModel.default
        let engine = SpeechEngineFactory.make(
            kind: kind, model: model, modelFolder: modelStore.location(of: model),
            idleAfter: BackedSpeechEngine.idleRelease)
        speechEngine = engine
        return engine
    }

    /// Hands the pipeline the recogniser just chosen, which it takes up once no dictation is under way.
    private func switchSpeechEngine(to kind: SpeechEngineKind) {
        let speech = makeSpeechEngine(kind)
        guard modelStore.isInstalled(.default) else {
            // Nothing to load until the download ends, which loads whichever recogniser is chosen by then.
            Task { [weak self] in
                guard let pipeline = self?.pipeline else { return }
                await pipeline.adopt(speech: speech, loading: false)
                self?.speechInUse = await pipeline.speechKind
                self?.refreshMainWindow()
            }
            return
        }
        loadSpeechModel { await $0.adopt(speech: speech) }
    }

    private func buildPipeline() {
        let speech = makeSpeechEngine(settings.engines.speech)
        speechInUse = speech.kind

        // Ranked against the screen the pipeline already read for this dictation, not a second read of its own.
        let speechWords = DictionaryVocabulary { [dictionary] in
            await (dictionary.allEntries(), Date())
        }

        // One cue for both ends, shaped when it can be and the plain system sound when it cannot.
        let sounds = RecordingSounds(
            player: FallbackSoundPlayer([ShapedSoundPlayer(), SystemSoundPlayer()]),
            enabled: settings.playsSoundWhenRecordingStarts)
        recordingSounds = sounds
        let cue = sounds.cue

        // Held so the floating button's meter reads the level without queueing behind a `stop()`.
        let microphone = AVAudioCaptureEngine(
            source: AVAudioEngineMicrophoneSource(), recordings: recordings, cue: cue)
        dock.setLevelSource { microphone.momentaryLevel }

        let pipeline = DictationPipeline(
            capture: microphone,
            speech: speech,
            cleaner: cleaner(for: settings),
            context: context,
            // Announced, like every write this app makes. See `Docs/insertion.md`.
            inserter: TextInsertion.coordinator(
                pasteboard: announcingPasteboard, reporting: Self.logPaste),
            speechWords: { seeing in await speechWords.vocabulary(favouring: seeing) },
            corrector: DictionaryCorrections(dictionary: dictionary),
            snippets: StoredSnippets(store: snippets),
            learner: StoreCounters(dictionary: dictionary, snippets: snippets),
            vocabulary: LearnedVocabulary(dictionary: dictionary),
            metrics: telemetry.map { MetricsFanOut([diagnostics, $0.recorder]) } ?? diagnostics,
            cleaningRecorder: diagnostics,
            destinationOverrides: settings.destinations,
            recordings: recordings,
            // A retry runs with Uttrflow's own window in front, so its words can only be copied.
            clipboard: TextInsertionCoordinator(strategies: [
                ClipboardTextInsertionEngine(pasteboard: announcingPasteboard)
            ]),
            profile: settings.profile
        )
        self.pipeline = pipeline

        controller = DictationController(
            pipeline: pipeline,
            monitor: ActivationMonitor(),
            cue: cue,
            activation: settings.hotkeyActivation,
            handsFreeEnabled: settings.handsFreeEnabled,
            clock: ContinuousClock(),
            onAdvice: { [weak self] advice in
                Task { @MainActor in self?.recordingAdviceChanged(to: advice) }
            },
            onStopGestureChange: { [weak self] gesture in
                Task { @MainActor in self?.recordingStopGestureChanged(to: gesture) }
            }
        )
    }

    /// Redraws the menu bar and the floating button as a recording nears its cap.
    private func recordingAdviceChanged(to advice: DictationAdvice) {
        guard advice != recordingAdvice else { return }
        recordingAdvice = advice
        refreshMenuBar()
        dock.update(with: dockPresentation(for: lastDictationState))
    }

    /// Redraws the floating button when the gesture that ends a recording has changed.
    private func recordingStopGestureChanged(to gesture: StopGesture) {
        guard gesture != recordingStopGesture else { return }
        recordingStopGesture = gesture
        dock.update(with: dockPresentation(for: lastDictationState))
    }

    private func wireInterface() {
        guard let pipeline else { return }

        menuBar.onCommand = { [weak self] intent in self?.carryOut(intent) }
        menuBar.onMenuWillOpen = { [weak self] in
            self?.checkSecureInput()
            self?.refreshMenuClips()
        }
        secureInputObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSecureInput() }
        }

        // Submitted, not handled: the controller queues gestures so press and release cannot interleave.
        dock.onPressBegan = { [weak self] in
            guard self?.isSignedIn == true else { return }
            self?.controller?.submit(.pressed)
        }
        // Not gated, so a hold begun before a sign-out still ends.
        dock.onPressEnded = { [weak self] in self?.controller?.submit(.released) }
        // A toggle, not a press and a release: VoiceOver activates the button and has nothing to hold.
        dock.onToggle = { [weak self] in self?.toggleDictation() }
        dock.onRecoveryAction = { [weak self] action in self?.perform(action) }

        dock.setShortcut(SettingsShortcut.compact(settings.hotkey))
        dock.setShrinksToGrip(settings.shrinksToGripWhenIdle)
        checkSecureInput()
        showTheFloatingButtonIfWanted()

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

    /// Why the shortcut is not armed, shown until it is; retried on the way back in.
    private lazy var shortcutArming = ShortcutArming { [weak self] in self?.showShortcutUnheard() }
    /// Claimed shortcuts the window server refused, so a row never shows a key that does nothing.
    private var unarmedShortcuts: Set<ShortcutAction> = [] {
        didSet {
            guard unarmedShortcuts != oldValue else { return }
            settingsPage.setUnarmedShortcuts(unarmedShortcuts)
        }
    }

    /// Arms the dictation shortcut while dictation is on, and releases it while it is off.
    private func startWatchingForTheShortcut() {
        guard let controller else { return }
        guard surfaces.listensForDictation else {
            shortcutArming.disarm()
            Task { await controller.stop() }
            return
        }
        let binding = settings.hotkey
        let arming = shortcutArming
        // Kept as its own state on the menu bar and floating button, never shown as a failed dictation.
        Task {
            await arming.arm { () throws(HotkeyError) in try await controller.start(binding: binding) }
            if let failure = arming.failure {
                let reason = SuggestionLog.failure(failure)
                Self.log.error("the dictation shortcut is not armed: \(reason, privacy: .public)")
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
        quickPanel.onIntent = { [weak self] intent, behind in self?.carryOut(intent, behind: behind) }

        followTheClipboardSwitch()
        startWatchingForClaimedShortcuts()
    }

    /// Records copies while the Clipboard switch is on, and stops recording the moment it is off.
    private func followTheClipboardSwitch() {
        guard surfaces.watchesTheClipboard else {
            clipboardWatchTask?.cancel()
            clipboardWatchTask = nil
            return
        }
        guard clipboardWatchTask == nil else { return }
        // Built out here: a `[weak self]` closure nested in another captures the outer binding.
        let arrived: @Sendable (NoticedClip) async -> Void = { [weak self] noticed in
            await self?.clipArrived(noticed)
        }
        // Read now, so a copy made after the switch went on is recorded even if the task starts late.
        let baseline = clipboardWatcher.changeCount
        // Utility, because a poll nobody is waiting on should not run as the main thread's work.
        clipboardWatchTask = Task(priority: .utility) { [clipboardWatcher] in
            // Whatever was copied while the switch was off stays unrecorded.
            await clipboardWatcher.passOver(upTo: baseline)
            await clipboardWatcher.run(handing: arrived)
        }
    }

    /// Keeps a clip the user has just copied, and shows it if they are looking.
    private func clipArrived(_ noticed: NoticedClip) async {
        await keep(noticed)
        await refreshPanelIfOpen()
        await readMenuClips()
    }

    /// Rereads the popover's clips in the background and redraws once they are in.
    private func refreshMenuClips() {
        Task { [weak self] in await self?.readMenuClips() }
    }

    /// The newest few clips for the popover, or none while the clipboard is switched off.
    private func readMenuClips() async {
        let clips =
            settings.clipboardEnabled
            ? Array(await clipboard.clips(keeping: retention).prefix(MenuBarPresenter.clipCount)) : []
        guard clips != menuClips else { return }
        menuClips = clips
        refreshMenuBar()
    }

    /// Records one noticed clip; a refused write loses that clip, and giving up would lose all the rest.
    private func keep(_ noticed: NoticedClip) async {
        _ = try? await clipboard.record(noticed, keeping: retention)
    }

    /// One registration per claimed shortcut; a refusal is logged rather than shown as a dictation failure.
    private func startWatchingForClaimedShortcuts() {
        for task in claimedTasks.values { task.cancel() }
        claimedTasks.removeAll()
        for monitor in claimedHotkeys.values { monitor.stop() }
        claimedHotkeys.removeAll()

        var refused: Set<ShortcutAction> = []
        // Signed out, no key is claimed, so each one still reaches the app in front.
        for action in surfaces.claimedShortcuts {
            guard let binding = settings.shortcuts.first(for: action) else { continue }
            let monitor = CarbonHotkeyMonitor()
            do {
                try monitor.start(binding: binding)
            } catch {
                Self.log.error(
                    "\(action.rawValue, privacy: .public) shortcut refused: \(error.userMessage, privacy: .public)"
                )
                refused.insert(action)
                continue
            }
            claimedHotkeys[action] = monitor
            claimedTasks[action] = Task { [weak self] in
                for await event in monitor.events {
                    // Releases ignored: acting on key-up would punish a slow hand.
                    guard event == .pressed else { continue }
                    await self?.perform(action)
                }
            }
        }
        unarmedShortcuts = refused
    }

    /// Does what one claimed shortcut is for; internal so a test can press one.
    func perform(_ action: ShortcutAction) async {
        guard isSignedIn else { return }
        switch action {
        case .clipboard:
            await toggleQuickPanel()
        case .pasteLastTranscript:
            await pasteLastTranscript()
        case .copyLastTranscript:
            copyLastTranscript()
        // Watched through the tap rather than registered, so it never arrives here.
        case .dictate:
            break
        }
    }

    /// Puts the last dictation back at the caret by the route a dictation takes, never the clipboard.
    private func pasteLastTranscript() async {
        guard let text = lastTranscript, !text.isEmpty else {
            Self.log.notice("paste last transcript: nothing dictated yet")
            return
        }
        do {
            _ = try await clipInserter.insert(text)
        } catch {
            render(.failed(DictationFailure(error)))
        }
    }

    /// Writes the clipboard on purpose, which is the one shortcut whose whole job that is.
    private func copyLastTranscript() {
        guard let text = lastTranscript, !text.isEmpty else {
            Self.log.notice("copy last transcript: nothing dictated yet")
            return
        }
        announcingPasteboard.setText(text)
    }

    /// The shortcut is a toggle, so the same key puts the panel away again.
    private func toggleQuickPanel() async {
        guard isSignedIn else { return }
        guard !quickPanel.isVisible else {
            closeQuickPanel()
            return
        }
        // Fresh, and shown before anything is awaited, so the keys after the shortcut reach the search (#860).
        let opening = PanelSnapshot.opening(now: Date(), resuming: resume)
        panel = opening
        quickPanel.show(PanelPresenter.present(opening))
        panelTarget = quickPanel.insertionDestination
        updates.refresh()
        let opened = quickPanel.opens
        // A copy since the last poll is taken now, started not awaited, so no read holds the panel shut (#895).
        if settings.clipboardEnabled {
            let arrived: @Sendable (NoticedClip) async -> Void = { [weak self] noticed in
                await self?.clipArrived(noticed)
            }
            Task { [clipboardWatcher] in await clipboardWatcher.catchUp(handing: arrived) }
        }
        let placement = await placement()
        let dictation = await voice()
        // K4, B8 — asked once on the way in, so the presenter stays a function of its input.
        let folder = await clipboard.imagesFolder
        // Nothing is written into a panel this open no longer owns; a later one asks these again itself.
        guard quickPanel.opens == opened, panel != nil else { return }
        panel?.insertion = placement
        panel?.dictation = dictation
        panel?.imagesFolder = folder
        // A4 — said on the way in, not after Return, when there is nowhere left to say it.
        if case .clipboardOnly(let obstacle) = placement, obstacle == .accessibilityNotGranted {
            panel?.notice = obstacle.notice
        }
        if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
        // The list comes by the one path a copy arriving also takes, so neither can undo the other.
        await refreshPanelIfOpen()
    }

    /// B3–B5 — whether Return will place a clip or only copy it, asked while there is still somewhere to say so.
    private func placement() async -> PanelInsertion {
        // The two questions only the machine can answer; the rule is `PanelInsertion.decided`.
        await PanelInsertion.decided(
            isAccessibilityGranted: accessibility.status() == .granted,
            isSelfFrontmost: focus.isSelfFrontmost())
    }

    /// B8, D5 — what only the machine knows about a list, asked on opening and on every refresh alike.
    private func facts(
        about clips: [Clip]
    ) async -> (missing: Set<Clip.ID>, formattable: Set<CodeLanguage>) {
        (await missingPictures(among: clips), await formattable(among: clips))
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
            if !(await clipboard.hasImage(for: image)) { missing.insert(clip.id) }
        }
        return missing
    }

    /// I6, I7 — whether dictation can start and why not, so a dimmed button carries its reason.
    private func voice() async -> PanelDictation {
        guard await microphone.status() == .granted else {
            return .unavailable(.microphoneNotGranted)
        }
        // The same question the menu bar asks: loaded, not merely on disk.
        switch speechReadiness {
        case .ready: return .ready
        case .loading: return .unavailable(.modelLoading)
        case .downloading, .loadFailed, .loadFailedAgain, .incomplete, .notInstalled:
            return .unavailable(.modelNotReady(percent: nil))
        }
    }

    /// A8 — answers a key or click in the panel, which only copies when the application the caret belonged to has quit.
    private func panelAnswered(_ key: PanelKey, behind: NSRunningApplication? = nil) {
        guard let snapshot = panel else { return }
        // Any key means the panel is in use; a notice below starts the wait again.
        noticeLinger.interrupt()
        let response = snapshot.applying(key, caretOwnerHasQuit: behind?.isTerminated == true)
        panel = response.state
        perform(response.outcome.effect)
    }

    /// Carries out what an answered keystroke or row button asks, against the panel as it now stands.
    private func perform(_ effect: PanelEffect) {
        switch effect {
        case .redraw:
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
        case .close:
            closeQuickPanel()
        case .closeAndInsertImage(let clip):
            closeQuickPanel()
            insertImage(clip)
        case .say(let notice):
            // Stays open, or the sentence describes a clip the user cannot see.
            panel?.notice = notice
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            closeAfterReading()
        case .closeAndInsertFormatted(let text, let richText, let used):
            let destination = panelTarget ?? InsertionDestination(applicationName: nil, bundleIdentifier: nil)
            closeQuickPanel()
            insert(text, richText: richText, targeting: destination, used: used)
        case .closeAndInsert(let text, let used):
            // Closed first: insertion declines outright while Uttrflow is frontmost.
            let destination = panelTarget ?? InsertionDestination(applicationName: nil, bundleIdentifier: nil)
            closeQuickPanel()
            insert(text, targeting: destination, used: used)
        case .closeAndInsertConcealed(let text, let used):
            let destination = panelTarget ?? InsertionDestination(applicationName: nil, bundleIdentifier: nil)
            closeQuickPanel()
            insert(text, concealed: true, targeting: destination, used: used)
        case .copyAndSay(let text, let notice, let used):
            // Stays open: the panel is the only surface left to say this on.
            putOnClipboard(text, used: used)
            panel?.notice = notice
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            closeAfterReading()
        case .copyConcealedAndSay(let text, let notice, let used):
            putOnClipboard(text, concealed: true, used: used)
            panel?.notice = notice
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            closeAfterReading()
        case .copyImageAndSay(let clip, let notice):
            let owner = PanelLateRequest(opens: quickPanel.opens, sheet: panel?.sheet)
            Task { [weak self] in
                guard let self else { return }
                let copied = await putImageOnClipboard(clip)
                guard owner.isSameOpen(panel, opens: quickPanel.opens) else { return }
                // A picture that went between the draw and the keypress is said, never claimed as copied.
                panel?.notice = copied ? notice : Self.pictureMissingNotice(clip)
                if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
                closeAfterReading()
            }
        case .closeAndCopy(let text, let richText, let used):
            // Onto the clipboard and no further: the user will paste it somewhere else.
            putOnClipboard(text, richText: richText, used: used)
            closeQuickPanel()
        case .closeAndCopyConcealed(let text, let used):
            putOnClipboard(text, concealed: true, used: used)
            closeQuickPanel()
        case .closeAndCopyImage(let clip):
            closeQuickPanel()
            Task { [weak self] in _ = await self?.putImageOnClipboard(clip) }
        case .applyAndRedraw(let change):
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            apply(change)
        }
    }

    /// The notice for a picture whose file has gone, worded as Return words it.
    private static func pictureMissingNotice(_ clip: Clip) -> PanelNotice? {
        guard case .say(let notice) = PanelOutcome.pictureMissing(clip).effect else { return nil }
        return notice
    }

    /// Carries out a change and redraws from what the store hands back, never from what was asked.
    private func apply(_ change: PanelChange) {
        let owner = PanelLateRequest(opens: quickPanel.opens, sheet: panel?.sheet)
        Task {
            do {
                try await carryOut(change)
            } catch let failure as ClipboardStoreError {
                // F10 — stays open holding the failure, which must look different from a success.
                Self.log.error(
                    "clipboard write refused: \(failure.userMessage, privacy: .public)")
                guard owner.isSameOpen(panel, opens: quickPanel.opens) else { return }
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
        case .setPinned(let id, let isPinned):
            _ = try await clipboard.setPinned(isPinned, of: id, keeping: retention)
        case .delete(let id):
            // F7, F9 — kept in hand, because the store forgets it the moment this returns.
            let held = panel?.clips.first { $0.id == id }
            let ticket = undoOffer.offer(held)
            // The earlier delete's timer must not expire this one's offer before its own starts.
            undoTask?.cancel()
            panel?.canUndoDelete = held != nil
            panel?.undoAnnouncementID = UUID()
            Self.log.info(
                "delete: undoable=\(held != nil, privacy: .public) flag=\(self.panel?.canUndoDelete == true, privacy: .public)"
            )
            // Only the latest delete can be undone, so an earlier one's picture is let go first.
            await clipboard.forgetHeldPictures()
            _ = try await clipboard.delete(id, keeping: retention, holdingPicture: held != nil)
            // A later delete owns the offer and its timer, so a superseded one leaves both alone.
            guard undoOffer.isLatest(ticket) else { return }
            await startForgettingTheUndo()
        case .create(let text):
            // Detected here, off the main actor: the panel knows what was typed, not what a string is.
            let classified = await ClipKindDetector.classify(text)
            let clip = Clip(
                text: text, kind: classified.kind, copiedAt: Date(), source: nil,
                // Typed into the panel and kept, so it belongs with what the app made.
                origin: .uttrflow,
                language: classified.language)
            _ = try await clipboard.record(clip, keeping: retention)
        case .rewriteText(let id, let tidied):
            _ = try await clipboard.setText(tidied, of: id, keeping: retention)
        case .setRichText(let id, let note):
            _ = try await clipboard.setRichText(note, of: id, keeping: retention)
        case .renameCategory(let from, let to):
            // Every clip under the old name moves; no alias is touched, because a collection is a shelf.
            _ = try await clipboard.moveCategory(from, to: to, keeping: retention)
        case .deleteCategory(let name, let destination):
            _ = try await clipboard.moveCategory(name, to: destination, keeping: retention)
        case .deleteCategoryAndClips(let name):
            _ = try await clipboard.deleteCategory(name, keeping: retention)
        case .restore(let clip):
            _ = try await clipboard.record(clip, keeping: retention)
            await clipboard.forgetHeldPictures()
            undoOffer.withdraw()
            panel?.canUndoDelete = false
        }
    }

    /// Expires the undo offer, so an old delete cannot be reversed by a keystroke meant for something else.
    private func startForgettingTheUndo() async {
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: AppDelegate.undoWindow)
            guard !Task.isCancelled else { return }
            await self?.clipboard.forgetHeldPictures()
            self?.undoOffer.withdraw()
            self?.panel?.canUndoDelete = false
            await self?.refreshPanelIfOpen()
        }
    }

    /// The row's own buttons, for the ones the panel cannot answer alone.
    private func carryOut(_ intent: PanelIntent, behind: NSRunningApplication? = nil) {
        // Any row button means the panel is in use; a notice below starts the wait again.
        noticeLinger.interrupt()
        // Insert and reveal go the path Return goes, quit check included, so a click and a key mean one clip.
        if let key = intent.key {
            panelAnswered(key, behind: behind)
            return
        }
        if let change = intent.immediateChange {
            apply(change)
            return
        }

        switch intent {
        case .pin, .unpin:
            // These are routed through `immediateChange` above.
            break
        case .copy(let id):
            // Through the panel, so a picture is copied as a picture and a missing one is said.
            guard let response = panel?.copying(id) else { return }
            panel = response.state
            perform(response.outcome.effect)
        case .keepQuery(let text):
            apply(.create(text))
        case .dictate:
            // Closed first, then the ordinary dictation, so one place describes it.
            closeQuickPanel()
            toggleDictation()
        case .openAccessibilitySettings:
            closeQuickPanel()
            Task { await openSettingsPane(.accessibility) }
        case .undoDelete:
            Self.log.info("undo requested: have=\(self.undoOffer.clip != nil, privacy: .public)")
            guard let clip = undoOffer.clip else { return }
            undoTask?.cancel()
            apply(.restore(clip))
        case .format(let id):
            runFormatter(on: id)
        case .openSettings:
            // Closed first: Settings activates the app, and the panel would belong to nothing.
            closeQuickPanel()
            show(.settings(.general))
        case .insert, .reveal, .alias, .move, .delete, .renameCategory, .deleteCategory,
            .reindent, .makeNote, .scope:
            // Answered above, by `intent.key`.
            break
        }
    }

    /// D5–D7 — runs the formatter and guards its output before anybody is offered a diff.
    private func runFormatter(on id: Clip.ID) {
        guard let clip = panel?.clips.first(where: { $0.id == id }), let language = clip.language
        else { return }
        formatterRuns += 1
        let request = PanelFormatRequest(
            owner: PanelLateRequest(opens: quickPanel.opens, sheet: panel?.sheet),
            clip: id, text: clip.text, run: formatterRuns)

        Task { [formatter] in
            guard let produced = await formatter.format(clip.text, as: language) else {
                Self.log.info("formatter produced nothing for \(language.rawValue, privacy: .public)")
                return
            }
            let original = clip.text
            // Guarded and compared off the main actor, because both walk the whole clip.
            let prepared = await Task.detached(priority: .utility) { () -> PreparedFormattingSheet?? in
                guard FormatterGuard.isFaithful(produced, to: original) else { return .none }
                guard produced != original else { return .some(nil) }
                return .some(PreparedFormattingSheet(from: original, to: produced))
            }.value
            guard let prepared else {
                // Logged loudly: a formatter changing what code means, caught by the guard.
                Self.log.error(
                    "formatter output discarded: not faithful (\(language.rawValue, privacy: .public))"
                )
                return
            }
            guard produced != clip.text else { return }
            // A panel closed, reopened, re-sheeted, edited or formatted again since is left alone.
            guard request.accepts(into: panel, opens: quickPanel.opens, latestRun: formatterRuns)
            else { return }
            guard let prepared else { return }
            panel?.remember(prepared)
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

    /// Puts a picture's PNG on the clipboard through the one pasteboard; false when its file has gone.
    private func putImageOnClipboard(_ clip: Clip) async -> Bool {
        guard let image = clip.image, let data = await clipboard.imageData(for: image) else {
            Self.log.error("picture missing at copy: \(clip.id, privacy: .public)")
            return false
        }
        markUsed(clip.id)
        announcingPasteboard.setImage(data)
        return true
    }

    /// K4 — pastes a picture, on its own path because the Accessibility route writes only strings.
    private func insertImage(_ clip: Clip) {
        markUsed(clip.id)
        Task { [weak self, clipboard, pasteboard = announcingPasteboard, focus] in
            guard let image = clip.image, let data = await clipboard.imageData(for: image) else {
                // B8 from the other side: the file went between the draw and the keypress.
                Self.log.error("picture missing at paste: \(clip.id, privacy: .public)")
                self?.reportPanelPaste(.pictureMissing)
                return
            }
            do {
                // Named by its bytes, so a copy landing in the same tick is not claimed by this write.
                try PasteboardImageInsertionEngine(
                    focus: focus, pasteboard: pasteboard, keystrokes: CGEventKeystrokeSender()
                ).insert(data)
            } catch let failure as TextInsertionError {
                // The image may already be on the clipboard if focus changes during the write.
                Self.log.error(
                    "picture paste refused: \(failure.userMessage, privacy: .public)")
                self?.reportPanelPaste(.pictureRefused)
            }
        }
    }

    /// Removes Uttrflow's own clipboard copies of a forgotten dictation, found by its identifier.
    private func forgetClips(of dictation: DictationRecord.ID, saying spoken: String?) async throws {
        let retention = ClipRetention(
            days: settings.clipboardRetentionDays, now: Date(),
            dictationDays: settings.transcriptRetentionDays)
        try await clipboard.deleteCopies(ofDictation: dictation, saying: spoken, keeping: retention)
        await refreshPanelIfOpen()
    }

    /// Keeps a dictation in the clipboard's Uttrflow list while the Clipboard switch is on, and nothing while it is off.
    @discardableResult
    func recordAsClip(_ text: String, of dictation: DictationRecord.ID) -> Task<Void, Never>? {
        guard surfaces.watchesTheClipboard else { return nil }
        return Task { [clipboard] in
            let classified = await ClipKindDetector.classify(text)
            let clip = Clip(
                text: text, kind: classified.kind, copiedAt: Date(), source: ClipOrigin.dictationSource,
                // Which keeps it out of History, where it would be the newest thing every time.
                origin: .uttrflow, dictations: [dictation],
                language: classified.language)
            _ = try? await clipboard.record(clip, keeping: retention)
            await refreshPanelIfOpen()
        }
    }

    /// Puts text where the caret is, through the coordinator whose last strategy cannot fail.
    private func insert(
        _ text: String, richText: String? = nil, concealed: Bool = false,
        targeting destination: InsertionDestination? = nil, used: Clip.ID?
    ) {
        markUsed(used)
        let clipInserter = concealed ? secretInserter : clipInserter
        Task { [weak self, clipInserter] in
            do {
                let attempt: InsertionAttempt
                if let destination {
                    attempt = try await clipInserter.insert(text, richText: richText, targeting: destination)
                } else {
                    attempt = try await clipInserter.insert(text, richText: richText)
                }
                Self.log.info(
                    """
                    clip inserted by \(attempt.method.rawValue, privacy: .public) \
                    arrival=\(attempt.arrival.rawValue, privacy: .public)
                    """)
                self?.reportPanelPaste(.text(attempt))
            } catch {
                // Every strategy refused, including the one that cannot.
                let why = (error as? any UttrflowFailure)?.userMessage ?? SuggestionLog.failure(error)
                Self.log.error("clip insertion failed: \(why, privacy: .public)")
                self?.reportPanelPaste(.textRefused)
            }
        }
    }

    /// Says on the floating button, and aloud, what a panel paste left undone; the panel has already gone.
    private func reportPanelPaste(_ result: PanelPasteResult) {
        guard let report = PanelPasteReport.after(result) else { return }
        var spoken = AttributedString(report.spoken)
        spoken.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(spoken).post()
        // A dictation under way owns the button, and its own outcome is the newer news.
        guard case .idle = lastDictationState else { return }
        pasteReport = DictationPresenter.dock(
            notice: report.symbolName, primaryLine: report.primaryLine,
            secondaryLine: report.secondaryLine, accessibilityLabel: report.spoken)
        dock.update(with: dockPresentation(for: lastDictationState))
        pasteReportTask?.cancel()
        pasteReportTask = Task { [weak self] in
            try? await Task.sleep(for: Self.failureLingers)
            guard !Task.isCancelled, let self else { return }
            self.pasteReport = nil
            self.dock.update(with: self.dockPresentation(for: self.lastDictationState))
        }
    }

    /// Adds a copy made while the panel is open, without moving a selection held by identity.
    private func refreshPanelIfOpen() async {
        guard panel != nil, quickPanel.isVisible else { return }
        panelReads += 1
        let read = panelReads
        let clips = await clipboard.clips(keeping: retention)
        let facts = await facts(about: clips)
        // A read that started earlier never replaces a newer list, or a copy shown while opening would go.
        guard read == panelReads else { return }
        panel?.install(
            clips, missingImages: facts.missing, formattableLanguages: facts.formattable,
            now: Date())
        guard let snapshot = panel else { return }
        quickPanel.update(PanelPresenter.present(snapshot))
    }

    /// Through the one pasteboard, so the write is announced and stays on this Mac. See `Docs/insertion.md`.
    private func putOnClipboard(
        _ text: String, richText: String? = nil, concealed: Bool = false, used: Clip.ID?
    ) {
        markUsed(used)
        // A secret goes up marked, so no other clipboard history records it in plain text.
        guard !concealed else { return announcingPasteboard.setConcealedText(text) }
        // E2, E3 — both flavours, so the receiving application takes the one it understands.
        announcingPasteboard.setText(text, richText: richText)
    }

    /// Tells the user, on screen and through VoiceOver, that the words are on the clipboard, where the panel would have said so.
    private func sayCopiedForMainWindow() {
        let notice = MainNotice(
            message: "Copied — click where you want it, then press ⌘V",
            symbolName: "doc.on.clipboard", tone: .neutral)
        actionNotice = notice
        announce(notice.message, urgently: false)
        refreshMainWindow()
    }

    private func closeAfterReading() {
        noticeLinger.start { [weak self] in
            // A sheet opened meanwhile is work in progress, never closed under the person.
            guard self?.panel?.sheet == nil else { return }
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
        noticeLinger.interrupt()
        quickPanel.hide()
        panel = nil
        panelTarget = nil
        // The quiet minute an update waits for starts here, not at the next window event.
        updates.refresh()
    }

    // MARK: Relaying

    /// Internal so a test can end a dictation without a microphone.
    func render(_ state: DictationState) {
        getOutOfTheWay(for: state)
        telemetry?.observe(state, language: settings.profile.preferredLanguages.first)
        if case .inserted(let outcome) = state {
            lastCleanedBy = outcome.cleanedBy
            if settings.engines.resolvedTransformerPreference.first != outcome.cleanedBy {
                probeTransformers()
            }
        }
        // Recorded before the menu is drawn, and kept even when insertion failed. §19.
        switch state {
        case .inserted(let outcome):
            if speechInUse == .appleSpeech {
                appleSpeechLoadFailure = nil
            }
            Self.log.notice(
                """
                dictation finished: method=\(outcome.method.rawValue, privacy: .public) \
                characters=\(outcome.text.count, privacy: .public) \
                app=\(outcome.insertedInto ?? "unknown", privacy: .public) \
                corrections=\(outcome.changes.corrections.count, privacy: .public) \
                snippets=\(outcome.changes.snippets.count, privacy: .public) \
                secure=\(outcome.intoSecureField, privacy: .public)
                """)
            // A secure field's words are kept nowhere: not as the last transcript, in history, or as a clip.
            guard let kept = outcome.wordsToKeep,
                let record = DictationRecordMapping.record(for: state, when: Date(), id: UUID())
            else { break }
            lastTranscript = kept
            lastTranscriptID = record.id
            keep(record)
            // I4 — into the clipboard too, which the watcher never sees because this is not a copy.
            recordAsClip(kept, of: record.id)
        case .failed(let notice):
            if notice.speechEngineKind == .appleSpeech,
                case .modelLoadFailed? = notice.speechEngineError
            {
                appleSpeechLoadFailure = notice.speechEngineError
            }
            Self.log.error(
                """
                dictation failed: \(notice.message, privacy: .public) \
                salvaged=\(notice.transcript != nil, privacy: .public) \
                kept=\(notice.recovery == .retryFromRecording, privacy: .public)
                """)
            if notice.wordsToKeep != nil,
                let record = DictationRecordMapping.record(for: state, when: Date(), id: UUID())
            {
                // Not an empty set: unmeasured is a different fact from nothing changed.
                keep(record)
            }
        case .idle, .recording, .transcribing, .tidying, .inserting:
            break
        }
        // Whichever way it ended, the row that said "Retrying…" is not retrying any more.
        if case .inserted = state { retryingRecording = nil }
        if case .failed = state { retryingRecording = nil }
        // After each dictation, since a menu-bar-only user may never open the window that lists them.
        if case .inserted = state { sweepExpired() }
        if case .failed = state { sweepExpired() }

        // Kept here, where every change already arrives, so the updater need not ask the pipeline.
        lastDictationState = state
        updates.refresh()
        // The last page of onboarding fills its field with the first dictation.
        onboarding?.dictationChanged(to: state)
        // A dictation's own outcome is newer than any panel paste's report.
        if state != .idle { pasteReport = nil }
        DictationInProgress.shared.set(dictating: state.isBusy)
        completions?.dictationChanged(isDictating: state.isBusy)

        // Cleared as soon as the recording ends, so a countdown cannot outlive it.
        if !state.isListening {
            recordingAdvice = .keepGoing
            recordingStopGesture = .letGo
        }
        menuBar.update(with: MenuBarPresenter.present(menuBarState(for: state)))
        dock.update(with: dockPresentation(for: state))
        announce(DictationPresenter.announcement(for: state))
        // No page shows a dictation under way, so the pages are read and built only once it has ended.
        if !state.isBusy { refreshMainWindow() }

        scheduleDismissal(after: state)
    }

    /// Speaks a state change through VoiceOver, since focus stays in the app being typed into.
    private func announce(_ announcement: DictationAnnouncement?) {
        guard let announcement else { return }
        announce(announcement.text, urgently: announcement.isUrgent)
    }

    /// Speaks one line through VoiceOver; an urgent one interrupts what it is reading.
    private func announce(_ text: String, urgently: Bool) {
        let priority: NSAccessibilityPriorityLevel = urgently ? .high : .medium
        NSAccessibility.post(
            element: NSApplication.shared, notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: priority.rawValue])
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
                // Logged, not rendered: the dictation on screen by now may be a later one.
                Self.log.error("history note not saved: \(DictationFailure(error).message, privacy: .public)")
            }
        }
    }

    /// Records how long the receiving application took to take a paste, which nothing else can observe.
    @Sendable private nonisolated static func logPaste(_ outcome: PasteConfirmation.Outcome) {
        switch outcome {
        case .landed(let waited):
            log.notice(
                "paste landed after \(waited.inSeconds, format: .fixed(precision: 2), privacy: .public)s")
        case .notReported:
            log.notice("paste unconfirmed: the field does not report what it holds")
        case .gaveUp(let waited):
            log.notice(
                "paste not seen within \(waited.inSeconds, format: .fixed(precision: 2), privacy: .public)s")
        case .cancelled(let waited):
            let seconds = waited.inSeconds
            log.notice(
                "paste wait cancelled after \(seconds, format: .fixed(precision: 2), privacy: .public)s")
        }
    }

    /// Redraws the menu bar and the floating button's hint when secure keyboard entry turns on or off.
    private func checkSecureInput() {
        guard secureInput.check() else { return }
        let now = secureInput.isBlocking ? "on" : "off"
        Self.log.notice("secure keyboard entry \(now, privacy: .public)")
        showShortcutUnheard()
    }

    /// Redraws both surfaces that say why the shortcut cannot be heard.
    private func showShortcutUnheard() {
        dock.setShortcutUnheard(shortcutUnheard)
        refreshMenuBar()
    }

    /// Why the shortcut cannot be heard, for both surfaces that say so.
    private var shortcutUnheard: String? {
        ShortcutArming.unheard(
            secureInputBlocking: secureInput.isBlocking, failure: shortcutArming.failure)
    }

    /// Translates the pipeline's state into the menu's vocabulary, deciding nothing.
    private func menuBarState(for state: DictationState) -> MenuBarState {
        let activity: DictationActivity =
            switch state {
            case .idle, .failed: .idle
            case .recording: .listening
            case .transcribing, .tidying, .inserting: .working
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
            speechLoadElapsed: speechLoadStarted.map { $0.duration(to: .now) } ?? .zero,
            recordingAdvice: recordingAdvice,
            recents: recents.previews.map {
                MenuBarRecent(
                    title: $0.title,
                    fullText: $0.isSecret ? $0.title : $0.dictation.text,
                    isSecret: $0.isSecret)
            },
            clips: menuClips,
            updateProgress: updates.progress,
            canCheckForUpdates: UpdateController.isConfigured,
            features: MenuBarFeatures(settings),
            shortcuts: settings.shortcuts,
            unarmedShortcuts: unarmedShortcuts,
            shortcutUnheard: shortcutUnheard,
            suggestionUnheard: suggestionSecureInputNotice,
            suggestionModel: suggestionModel,
            activation: settings.hotkeyActivation,
            speechModelBytes: SpeechModel.default.downloadBytes
        )
    }

    /// Carries out whatever the menu was asked for; internal so a test can choose an item.
    func carryOut(_ intent: MenuBarIntent) {
        // Signed out, every item but Quit asks for sign-in instead.
        guard SessionGate.permits(intent, isSignedIn: isSignedIn) else { return show(.onboarding) }
        switch intent {
        case .startDictation, .stopDictation:
            toggleDictation()
        case .recover(let action):
            perform(action)
        case .insertRecent(let index):
            guard let recent = recents.entries[safe: index] else { return }
            // The app's own inserter: a fresh one would get the unannouncing pasteboard.
            insert(
                recent.text, concealed: DictationTextPresentation(recent.text).isSecret, used: nil)
        case .copyRecent(let index):
            guard let recent = recents.entries[safe: index] else { return }
            // And through the helper that announces the write, for the same reason.
            putOnClipboard(
                recent.text, concealed: DictationTextPresentation(recent.text).isSecret, used: nil)
        case .insertClip(let index):
            guard let clip = menuClips[safe: index] else { return }
            if clip.image != nil {
                insertImage(clip)
            } else {
                insert(clip.text, concealed: clip.kind == .secret, used: clip.id)
            }
        case .copyClip(let index):
            guard let clip = menuClips[safe: index] else { return }
            if clip.image != nil {
                Task { [weak self] in _ = await self?.putImageOnClipboard(clip) }
            } else {
                putOnClipboard(
                    clip.text, richText: clip.richText, concealed: clip.kind == .secret, used: clip.id)
            }
        case .open(let destination):
            show(destination)
        case .openClipboard:
            Task { await toggleQuickPanel() }
        case .setFeature(let feature, let isOn):
            apply(.toggle(feature.setting, isOn: isOn))
            refreshMenuBar()
        case .checkForUpdates:
            updates.checkForUpdates()
        case .quit:
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: Windows

    /// Opens whichever surface was asked for, so nothing else knows which class owns a window.
    private func show(_ destination: UttrflowUX.Destination) {
        // The one gate every window passes: with no session, whatever was asked for, sign-in opens.
        let routed = SessionGate.route(destination, isSignedIn: isSignedIn)
        lastOpened = routed
        if case .settings(.diagnostics) = routed { probeTransformers() }
        guard drawsWindows else { return }
        switch routed {
        case .onboarding:
            // Not `presentOnboardingIfNeeded()`, which returns silently once the flow is finished.
            presentOnboarding()
        case .settings(let tab):
            settingsPage.open(tab)
            let window = mainWindow ?? makeMainWindow()
            mainWindow = window
            window.showSettings(settingsPage.model)
            // So the sidebar's Settings row lights up as the page appears.
            refreshMainWindow()
        case .main(let tab):
            let window = mainWindow ?? makeMainWindow()
            mainWindow = window
            window.show(tab)
            refreshMainWindow()
        }
    }

    /// Where the last request to open a surface went after the gate; internal so a test can read it.
    private(set) var lastOpened: UttrflowUX.Destination?
    /// Whether surfaces are put on screen; a test turns this off to read the gate without a window.
    var drawsWindows = true

    func makeMainWindow() -> MainWindowController {
        let window = MainWindowController(content: mainContent(measurements: []))
        window.onIntent = { [weak self] intent in self?.carryOut(intent) }
        window.onSearch = { [weak self] query in
            guard let self, let page = mainWindow?.page else { return }
            queries[page] = query
            redrawPages([page])
        }
        window.onScope = { [weak self] scope in
            guard let self, let page = mainWindow?.page else { return }
            scopes[page] = scope
            redrawPages([page])
        }
        window.onBecameVisible = { [weak self] in self?.catchUpMainWindow() }
        window.onVisibilityChange = { [weak self] in self?.homeClock.setVisible($0) }
        window.onSettingsLostFocus = { [weak self] in self?.settingsPage.surfaceDidLoseFocus() }
        window.onDraft = { [weak self] in
            guard let self else { return }
            // A refusal describes one attempt, and describes nothing once the typing changes.
            wordRefusal = nil
            snippetRefusal = nil
            redrawPages([.dictionary, .snippets])
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
        guard mainWindow.isOnScreen else {
            mainWindowIsBehind = true
            return
        }
        mainWindowIsBehind = false
        mainWindow.update(mainContent(measurements: lastMeasurements))
    }

    /// Re-presents only the editor pages when they are all a keystroke changed, and the whole window otherwise.
    private func redrawPages(_ pages: Set<MainTab>) {
        guard pages.isSubset(of: [.dictionary, .snippets]), !mainWindowIsBehind,
            let mainWindow, mainWindow.isOnScreen
        else { return redrawMainWindow() }
        var content = mainWindow.content
        let now = Date()
        if pages.contains(.dictionary) {
            content.dictionary = dictionaryPage(at: now, corrections: CorrectionHistory(of: kept).corrections)
        }
        if pages.contains(.snippets) { content.snippets = snippetsPage(at: now) }
        mainWindow.update(content)
    }

    /// Builds the pages skipped while the window was out of sight, from the last reading.
    private func catchUpMainWindow() {
        guard mainWindowIsBehind else { return }
        redrawMainWindow()
    }

    /// Forgets what a reset removed before redrawing, so the page cannot repaint the words it took.
    func forget(after reset: SettingsReset) {
        guard reset.forgetsTheLastDictation else {
            refreshMainWindow()
            return
        }
        lastCleaning = nil
        lastCleanedBy = nil
        forgetLastTranscript()
        Task { [weak self] in
            await self?.diagnostics.forget()
            self?.refreshMainWindow()
        }
    }

    /// Drops the words the paste and copy shortcuts put back, with the record they came from.
    private func forgetLastTranscript() {
        lastTranscript = nil
        lastTranscriptID = nil
    }

    /// Redraws from a fresh snapshot, reading everything on one hop so the pages agree.
    private func refreshMainWindow() {
        refreshGeneration += 1
        let reading = refreshGeneration
        Task { [weak self] in
            guard let self else { return }
            let measurements = await diagnostics.recorded
            lastMeasurements = measurements
            lastCleaning = await diagnostics.lastCleaning
            let kept = await history.records(
                keeping: Retention(days: settings.transcriptRetentionDays, now: Date()))
            self.kept = kept
            hasReadHistory = true
            knownRecordings = await recordings.waiting(now: Date())
            recents = RecentDictations(showing: kept)
            knownWords = await dictionary.allEntries()
            knownSnippets = await snippets.snippets()
            readAccount()
            await refreshPermissions()
            // The picture may need a round trip, so it follows the paint rather than holding it back.
            defer { Task { [weak self] in await self?.refreshPictureThenRedraw() } }
            // A later refresh has newer state, and painting over it would leave the older reading up.
            guard reading == refreshGeneration else { return }
            refreshMenuBar()
            // Read even out of sight, since the menu's Recent list comes from this reading too.
            guard mainWindow?.isOnScreen == true else {
                mainWindowIsBehind = true
                return
            }
            mainWindowIsBehind = false
            mainWindow?.update(mainContent(measurements: measurements))
        }
    }

    private func mainContent(measurements: [StageMeasurement]) -> MainContent {
        let now = Date()
        homeClock.drew(at: now)
        // Handed over whole: `HistoryEntry` is `DictationRecord`, so nothing is rebuilt.
        let entries = kept
        let shortcut = SettingsShortcut.compact(settings.hotkey)
        let changed = CorrectionHistory(of: entries)
        let corrections = changed.corrections

        return MainContent(
            notice: actionNotice,
            home: HomePresenter.page(
                for: HomeSnapshot(
                    permissions: knownPermissions, entries: entries,
                    account: knownEntitlement?.account,
                    // The name macOS knows, read here so a test decides who is greeted.
                    systemName: NSFullUserName(),
                    shortcut: shortcut, settings: settings, now: now,
                    speechModel: speechModelLoad, speechDownload: speechReadiness.download,
                    speechModelBytes: SpeechModel.default.downloadBytes, hasReadHistory: hasReadHistory)),
            sidebar: SidebarPresenter.sidebar(
                for: SidebarSnapshot(
                    // The page the window shows, which may be the Settings page on one of its tabs.
                    selection: mainWindow?.isShowingSettings == true
                        ? .settings(settingsPage.tab) : .page(mainWindow?.page ?? .home),
                    entries: entries,
                    correctionsToday: corrections.filter {
                        Calendar.autoupdatingCurrent.isDate($0.when, inSameDayAs: now)
                            && !$0.isUndone
                    }.count,
                    shortcutKeys: SettingsShortcut.keycaps(for: settings.hotkey), settings: settings,
                    version: .ofThisBuild,
                    now: now)),
            history: HistoryPresenter.page(
                for: HistorySnapshot(
                    entries: entries, query: query(for: .history), settings: settings,
                    keepsRecordings: true, recordings: knownRecordings,
                    retrying: retryingRecording, playing: playback.playing, now: now,
                    hasReadHistory: hasReadHistory)),
            dictionary: dictionaryPage(at: now, corrections: corrections),
            corrections: CorrectionsPresenter.page(
                for: CorrectionsSnapshot(
                    corrections: corrections, dictations: entries,
                    query: query(for: .corrections),
                    scope: CorrectionsScope(rawValue: scope(for: .corrections)) ?? .all,
                    settings: settings,
                    now: now)),
            insights: InsightsPresenter.page(
                for: InsightsSnapshot(
                    entries: entries, settings: settings,
                    range: InsightsRange(rawValue: scope(for: .insights)), now: now,
                    hasReadHistory: hasReadHistory)),
            snippets: snippetsPage(at: now),
            diagnostics: DiagnosticsPresenter.page(
                for: DiagnosticsSnapshot(
                    engines: settings.engines, speechInUse: speechInUse,
                    transformerAvailability: transformerAvailability,
                    speechModel: speechModelPresence, speechReadiness: speechReadiness,
                    appleSpeechStatus: appleSpeechStatus,
                    appleSpeechLoadFailure: appleSpeechLoadFailure,
                    permissions: knownPermissions,
                    measurements: measurements, cleaning: lastCleaning,
                    lastCleanedBy: lastCleanedBy,
                    suggestionModel: suggestionModel, version: .ofThisBuild,
                    machine: MachineDescription.current)),
            account: accountPage(at: now),
            shortcutKeycaps: SettingsShortcut.keycaps(for: settings.hotkey))
    }

    /// The Dictionary page as the last reading of the words draws it.
    private func dictionaryPage(at now: Date, corrections: [Correction]) -> DictionaryPresentation {
        DictionaryPresenter.page(
            for: DictionarySnapshot(
                entries: knownWords, draft: wordDraft, refusal: wordRefusal,
                query: query(for: .dictionary), filter: scope(for: .dictionary),
                corrections: corrections, now: now))
    }

    /// The Snippets page as the last reading of the snippets draws it.
    private func snippetsPage(at now: Date) -> SnippetsPresentation {
        SnippetsPresenter.page(
            for: SnippetsSnapshot(
                snippets: knownSnippets, draft: snippetDraft, refusal: snippetRefusal,
                query: query(for: .snippets), now: now))
    }

    /// Reads the account the pages draw from.
    func readAccount() {
        // The signed half only. See `Docs/entitlements.md`.
        let profile = account.profiles.load()
        knownEntitlement = profile?.entitlement
        // Displayed, never enforced, and only from a document that names the signed account.
        knownMemberSince = profile.flatMap { $0.isInternallyConsistent ? $0.account.createdAt : nil }
    }

    /// The Account page as the last reading of the account draws it.
    func accountPage(at now: Date) -> AccountPagePresentation {
        AccountPagePresenter.page(
            for: AccountPageSnapshot(
                entitlement: knownEntitlement,
                access: EntitlementGate(profiles: account.profiles)
                    .access(at: now, networkIsReachable: network.isReachable),
                now: now,
                picture: knownPicture?.bytes,
                memberSince: knownMemberSince,
                macName: MacName.current))
    }

    /// What one page is filtered by, asked per page because every page is rebuilt on each redraw.
    private func query(for page: MainTab) -> String { queries[page] ?? "" }
    private func scope(for page: MainTab) -> String { scopes[page] ?? "" }
    /// What the clean-up steps did to the last dictation, read on the same hop as the timings.
    private var lastCleaning: CleaningRecord?
    /// What the dictation pipeline last reported. See where it is written.
    private var lastDictationState: DictationState = .idle
    private var snippetEditorIsOpen = false
    /// The same, for the word editor.
    private var wordEditorIsOpen = false
    /// Why the last Save was refused, per editor, until the next keystroke clears it.
    private var wordRefusal: String?
    private var snippetRefusal: String?
    /// Why the last delete, flag, restore or undo did not happen, until one of them works or the page changes.
    private(set) var actionNotice: MainNotice?

    /// Counts editor requests, so a slow one cannot open over a faster one that followed it.
    private var editorGeneration = 0
    /// The same for redraws, which suspend six times and so can land out of order.
    private var refreshGeneration = 0
    /// Redraws home as the clock crosses a mood boundary or midnight, while the window is in sight.
    private lazy var homeClock = HomeClock { [weak self] in self?.redrawMainWindow() }

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
    /// When the signed-in account was created, from the unsigned profile beside the entitlement.
    private var knownMemberSince: Date?
    /// The person's picture and the path it came from, kept together so it is fetched once per account.
    private var knownPicture: (path: String, bytes: Data)?
    /// The timings last read, so a keystroke redraws without hopping to the actor.
    private var lastMeasurements: [StageMeasurement] = []
    /// Whether the main window's pages were last skipped because it was out of sight.
    private var mainWindowIsBehind = false
    /// Everything the store keeps, which is not ``recents`` — that is the menu's five.
    private var kept: [DictationRecord] = []
    /// Whether ``kept`` has been read yet, so Home never shows its first-run page before it knows.
    private var hasReadHistory = false
    /// Recordings whose words were lost, as of the last refresh.
    private var knownRecordings: [KeptRecording] = []
    /// The recording the pipeline is running again, so its row can say so.
    private var retryingRecording: UUID?
    /// The kept recording History is playing back, one at a time.
    private lazy var playback: RecordingPlayback = {
        let playback = RecordingPlayback()
        playback.onChange = { [weak self] in self?.redrawMainWindow() }
        return playback
    }()

    /// Clears the "Retrying…" badge of a retry the pipeline refused or abandoned.
    private func dropRetryingBadge(_ id: UUID) {
        guard retryingRecording == id else { return }
        retryingRecording = nil
        redrawMainWindow()
    }

    /// The last answer each gate gave; absent means unchecked, which the pages draw as silence.
    private var knownPermissions: [PermissionKind: PermissionStatus] = [:]

    /// Reads the account picture and redraws only when it changed.
    private func refreshPictureThenRedraw() async {
        let before = knownPicture?.path
        await refreshPicture()
        if knownPicture?.path != before { redrawMainWindow() }
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
        case .copy(let text):
            putOnClipboard(text, concealed: DictationTextPresentation(text).isSecret, used: nil)
            sayCopiedForMainWindow()
        case .insert(let text): insert(text, used: nil)
        case .dictate:
            toggleDictation()
        case .search:
            carryOut(.show(.history))
            mainWindow?.focusSearch()
        case .show(let page):
            // A notice describes the button that was pressed on the page being left, so it goes with it.
            actionNotice = nil
            mainWindow?.show(page)
            // Redrawn from what was last read: nothing on disk changed by moving tabs.
            redrawMainWindow()
        case .change(let change): apply(change)

        case .retryRecording(let id):
            if playback.playing == id { playback.stop() }
            retryingRecording = id
            redrawMainWindow()
            Task { [weak self] in
                guard let self, await self.pipeline?.retry(id) != true else { return }
                self.dropRetryingBadge(id)
            }
        case .forgetRecording(let id):
            if playback.playing == id { playback.stop() }
            act { [weak self] in await self?.recordings.discard(id) }
        case .playRecording(let id):
            guard playback.playing != id else { return playback.stop() }
            Task { [weak self] in
                guard let self, let audio = try? await self.recordings.audio(of: id) else { return }
                self.playback.play(WAVEncoder.encode(audio), id: id)
            }

        case .forgetDictation(let id):
            if id == lastTranscriptID { forgetLastTranscript() }
            let retention = Retention(days: settings.transcriptRetentionDays, now: Date())
            act { [weak self] in
                guard let self else { return }
                // Both files, the copy first, so a refused write leaves the record to delete again.
                let spoken = await self.history.records(keeping: retention)
                    .first { $0.id == id }?.text
                try await self.forgetClips(of: id, saying: spoken)
                try await self.history.delete(id, keeping: retention)
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
            openingEditor = Task { [weak self] in
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
            presentOnboarding()
        case .dismissNotice:
            actionNotice = nil
            redrawMainWindow()
        case .signOut:
            // Cleared first and the server told after, so signing out never waits on a network.
            account.profiles.clear()
            // Read again now, so the Account page stops naming the account before any redraw.
            readAccount()
            intentWork = Task { [account] in await account.authentication.signOut() }
            followSession()

        case .undoCorrection(let id):
            let retention = Retention(days: settings.transcriptRetentionDays, now: Date())
            act { [weak self] in
                guard let self else { return }
                // In order: the history decides there was something to undo before the dictionary hears of it.
                guard let entryID = try await history.undoCorrection(id, keeping: retention) else {
                    return
                }
                _ = try await dictionary.recordRevert(of: entryID)
            }

        case .flagDictation(let id):
            let retention = Retention(days: settings.transcriptRetentionDays, now: Date())
            act { try await self.history.toggleFlag(id, keeping: retention) }
        }
    }

    /// Applies a setting through ``SettingsEditor``, so two screens cannot apply one choice two ways.
    private func apply(_ change: SettingsChange) {
        // A request to act now rather than a change, so there is no `Settings` to save.
        if change.isRequestToAct {
            switch change {
            case .checkForUpdatesNow: updates.checkForUpdates()
            case .chooseApplicationToTurnOffSuggestions:
                // Applied through the Settings page, whose own copy of the settings would otherwise go stale.
                ApplicationPicker.choose(given: settings.suggestions) { [weak self] identifier in
                    self?.settingsPage.apply(.suggestionsHere(application: identifier, isOn: false))
                }
            case .retrySuggestionModel:
                guard settings.suggestions.isEnabled, suggestionModel == .failed else { return }
                prepareTheModelIfNeeded()
            case .openPage(let page): show(.main(page))
            default: break
            }
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
        intentWork = Task { [weak self] in
            do {
                try await change()
                // Cleared only on success, so the last refusal stays up until something works.
                self?.actionNotice = nil
            } catch {
                self?.report(error)
            }
            self?.refreshMainWindow()
        }
    }

    /// Puts a refused change on the page and through VoiceOver as well as in the log, so it is never silent.
    private func report(_ error: any Error) {
        let notice = MainNotice(refusing: error)
        Self.log.error(
            "store change refused: \(notice.message, privacy: .public) \(SuggestionLog.failure(error), privacy: .public)"
        )
        actionNotice = notice
        announce(notice.message, urgently: true)
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
        intentWork = Task { [weak self] in
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
        intentWork = Task { [weak self] in
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
        settingsPage.synchronize(settings: updated)
        recordingSounds?.apply(updated)
        applyAppearance()
        applyLaunchAtLogin()

        // Acted on here, or the shortcut relabels itself and the old key keeps working.
        if updated.hotkey != previous.hotkey || updated.dictationEnabled != previous.dictationEnabled {
            startWatchingForTheShortcut()
        }
        // Every registered key is re-armed together, or a changed one keeps firing the old binding.
        if updated.shortcuts != previous.shortcuts || updated.clipboardEnabled != previous.clipboardEnabled {
            startWatchingForClaimedShortcuts()
        }
        if updated.clipboardEnabled != previous.clipboardEnabled {
            followTheClipboardSwitch()
        }
        // The menu's ticks are these settings, so a change made in Settings redraws them.
        if MenuBarFeatures(updated) != MenuBarFeatures(previous) {
            refreshMenuBar()
        }
        if updated.hotkeyActivation != previous.hotkeyActivation {
            let activation = updated.hotkeyActivation
            Task { [weak self] in await self?.controller?.setActivation(activation) }
        }
        if updated.handsFreeEnabled != previous.handsFreeEnabled {
            let enabled = updated.handsFreeEnabled
            Task { [weak self] in await self?.controller?.setHandsFreeEnabled(enabled) }
        }
        telemetry?.setEnabled(updated.sharesUsageStatistics)
        // As above: a switch that drew itself and changed nothing.
        if updated.installsUpdatesAutomatically != previous.installsUpdatesAutomatically {
            updates.setInstallsAutomatically(updated.installsUpdatesAutomatically)
        }
        if updated.sendsCrashReports != previous.sendsCrashReports {
            crashReports.follow(isEnabled: updated.sendsCrashReports)
        }
        // A freshly built cleaner, so the next dictation runs the choices just made.
        if updated.cleaning != previous.cleaning || updated.destinations != previous.destinations
            || updated.engines != previous.engines
        {
            probeTransformers()
            let tidier = cleaner(for: updated)
            let overrides = updated.destinations
            Task { [weak self] in
                await self?.pipeline?.adopt(cleaner: tidier, destinationOverrides: overrides)
            }
        }
        // The recogniser is swapped between dictations, never under one, and loaded as at launch.
        if updated.engines.speech != previous.engines.speech {
            switchSpeechEngine(to: updated.engines.speech)
        }
        // The languages the user speaks steer recognition from the next dictation on.
        if updated.profile != previous.profile {
            let profile = updated.profile
            Task { [weak self] in await self?.pipeline?.adopt(profile: profile) }
        }
        // The master switch on the Suggestions screen is what builds and unbuilds the loop.
        if updated.suggestions != previous.suggestions {
            suggestionsChanged()
        }

        dock.setShortcut(SettingsShortcut.compact(settings.hotkey))
        dock.setShrinksToGrip(settings.shrinksToGripWhenIdle)
        showTheFloatingButtonIfWanted()
        refreshMainWindow()
    }

    /// Shows the floating button when the setting asks for it and somebody is signed in, and hides it otherwise.
    private func showTheFloatingButtonIfWanted() {
        guard surfaces.showsTheFloatingButton, drawsWindows else { return dock.hide() }
        dock.setAnchor(settings.floatingButtonAnchor)
        dock.show()
    }

    /// Whether the floating button collapses to a grip when idle, as the running button has it now.
    var dockShrinksToGrip: Bool { dock.shrinksToGrip }

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

    /// How long a finished state stays up, or `nil` for a state that is not finished.
    static func linger(after state: DictationState) -> Duration? {
        switch state {
        // Copied rather than typed asks the user to paste, so it stays as long as a failure.
        case .inserted(let outcome) where outcome.method == .clipboard: failureLingers
        case .inserted: successLingers
        // An informational notice asks nothing of the user, so it goes sooner.
        case .failed(let notice):
            notice.severity == .informational ? successLingers : failureLingers
        case .idle, .recording, .transcribing, .tidying, .inserting: nil
        }
    }

    /// Returns the interface to rest once the user has had time to read the result.
    private func scheduleDismissal(after state: DictationState) {
        dismissalTask?.cancel()
        guard let linger = Self.linger(after: state) else { return }

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
        // A failed load is retried by loading again, since a dictation would only repeat the wait.
        case .retry where speechReadiness == .loadFailed:
            loadSpeechModel()
        case .retry:
            // A toggle, not a synthesised keypress with no release to close it.
            toggleDictation()
        case .downloadSpeechModel where speechReadiness == .loadFailed || speechReadiness == .loadFailedAgain:
            repairSpeechModel()
        case .downloadSpeechModel:
            // Onboarding's setup page is the one surface that downloads the model and shows progress.
            show(.onboarding)
        case .pasteManually:
            // Already on the clipboard, put there by the insertion floor before it reported failure.
            Task { await pipeline?.acknowledge() }
        case .showRecentDictations:
            // Delivery was unconfirmed or the clipboard failed; Recent has the saved words.
            menuBar.openMenu()
        case .retryFromRecording:
            // The audio sits in today's list on History with its own Retry.
            show(.main(.history))
            Task { await pipeline?.acknowledge() }
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
        case .microphone:
            _ = await MicrophonePermissionGate().requestOrOpenSettings()
        case .appleIntelligence:
            SystemSettingsOpener().open(.appleIntelligence)
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

    func recordUse(ofEntries ids: [UUID]) async throws(DictationChangeError) {
        do {
            _ = try await dictionary.recordUse(of: ids)
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

/// A menu is built from a snapshot, so an index that has gone stale must do nothing.
extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
