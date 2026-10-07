import Accessibility
import AppKit
import OSLog
import UniformTypeIdentifiers
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

struct DismissalCountdown {
    private(set) var remaining: Duration
    private var startedAt: ContinuousClock.Instant?

    init(_ duration: Duration, at instant: ContinuousClock.Instant) {
        remaining = duration
        startedAt = instant
    }

    mutating func pause(at instant: ContinuousClock.Instant) {
        guard let startedAt else { return }
        remaining = max(.zero, remaining - startedAt.duration(to: instant))
        self.startedAt = nil
    }

    mutating func resume(at instant: ContinuousClock.Instant) {
        guard startedAt == nil, remaining > .zero else { return }
        startedAt = instant
    }

    func hasExpired(at instant: ContinuousClock.Instant) -> Bool {
        guard let startedAt else { return false }
        return startedAt.duration(to: instant) >= remaining
    }
}

enum DictationSessionEndObserver {
    static let screenIsLocked = Notification.Name("com.apple.screenIsLocked")

    static let notices = [
        NSWorkspace.sessionDidResignActiveNotification,
        NSWorkspace.screensDidSleepNotification,
        NSWorkspace.willSleepNotification,
    ]

    static func observe(
        in center: NotificationCenter, onEnd: @escaping @Sendable () -> Void
    )
        -> [any NSObjectProtocol]
    {
        notices.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in onEnd() }
        }
    }

    static func observeScreenLock(
        in center: NotificationCenter, onEnd: @escaping @Sendable () -> Void
    ) -> any NSObjectProtocol {
        center.addObserver(forName: screenIsLocked, object: nil, queue: .main) { _ in onEnd() }
    }
}

/// Assembles the product and relays between it and the interface, deciding nothing itself.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// Records which of the three insertion routes a dictation took, which nothing else can tell.
    private nonisolated static let log = Logger(
        subsystem: "com.uttrflow.Uttrflow", category: "insertion")

    private let settingsStore: UserDefaultsSettingsStore
    private let encryptedStore: EncryptedStore?
    /// The suggestion model's loaded weights, which also tidy dictation when Apple's model cannot.
    private let localTidier: (any CleanupModel)?
    private var settings = Settings()
    /// The pipeline's recording cue, told when the sound setting changes.
    private var recordingSounds: RecordingSounds?

    private let menuBar = MenuBarController()
    private let dock = DockPanelController()
    /// The last external app the user was typing in, retained while the menu itself is frontmost.
    private var suggestionApplicationBundleIdentifier: String?
    private var recents = RecentDictations()
    /// The newest clips as the popover last read them, resolved by identity when a row is chosen.
    private var menuClips: [Clip] = []
    /// Words the dictionary taught itself lately, offered in the popover because no window is open to say so.
    private(set) var recentlyLearned = RecentlyLearned()
    /// Where dictations are kept between launches, and the only thing that decides what is deleted.
    private let history: DictationHistoryStore
    /// Each dictation's audio, kept beside it only until its words land. See `Docs/recordings.md`.
    private let recordings: RecordingStore
    /// What the app observed about how this user speaks, under History's retention. See `Docs/learned-state.md`.
    private let evidence: EvidenceLedgerStore?
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
    private lazy var crashReports = CrashReporter(
        info: Bundle.main.infoDictionary ?? [:], sdk: LiveCrashReportingSDK(), layers: qualityLayers,
        onSend: { NetworkActivityLedger.shared.record(.crashReport) })
    /// Keeps the pipeline's stage timings for the session, which is what the diagnostics page reports on.
    private let diagnostics = DiagnosticsRecorder()
    /// Counts and timings, sent hourly unless Settings says not to. See `Docs/account-telemetry.md`.
    private var telemetry: UsageTelemetry?
    /// Whether secure keyboard entry is hiding the shortcut, checked on app switches and menu opens rather than on a timer.
    private let secureInput: SecureInputWatch
    private var secureInputObserver: (any NSObjectProtocol)?
    private var dictationSessionObservers: [any NSObjectProtocol] = []
    private var screenLockObserver: (any NSObjectProtocol)?

    /// Whether the recogniser can dictate, which is not whether its files are on disk.
    private var speechReadiness: SpeechModelReadiness = .notInstalled
    /// Why the last speech model load failed, as the pipeline classed it; Diagnostics names it.
    private var speechLoadFailure: SpeechLoadFailureClass?
    /// The input UID the next recording opens, read off the main actor at every open.
    private let chosenMicrophone = MicrophoneChoice()
    /// When the load under way began, so the estimate is said only once a load has run long enough to need it.
    private var speechLoadStarted: ContinuousClock.Instant?
    /// Redraws the load's estimate once a second while a load runs, and is gone once it ends.
    private var speechLoadTicker: Task<Void, Never>?
    /// The key release that starts the current wait, so a long wait can name its stage.
    private var waitStarted: ContinuousClock.Instant?
    /// Redraws the working line once a second while the wait after key release runs.
    private var waitTicker: Task<Void, Never>?
    /// Whether VoiceOver already knows this wait's stage; it hears it once.
    private var waitAnnounced = false
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
    /// The finished pieces' words while the key is held, drawn under the recording line.
    private var heardSoFar: String?
    private var heardTask: Task<Void, Never>?
    /// What the dock has to say to end a recording that is under way right now.
    private var recordingStopGesture: StopGesture = .letGo

    private var pipeline: DictationPipeline?
    /// The quality layers the pipeline is built with, read once from local defaults; Diagnostics shows the same value.
    private let qualityLayers = QualityLayers { key in
        let defaults = UserDefaults.standard
        return defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key)
    }
    /// Lets the app wiring test wait for a refused retry to finish without timing guesses.
    private(set) var retryWork: Task<Void, Never>?
    /// The pipeline's recogniser, held so memory pressure can let it go between dictations.
    private var speechEngine: BackedSpeechEngine?
    private var controller: DictationController<ContinuousClock>?
    private var stateTask: Task<Void, Never>?
    private var dismissalTask: Task<Void, Never>?
    private var dismissalCountdown: DismissalCountdown?
    private var dockHasAttention = false

    // MARK: The clipboard

    private let clipboard: ClipboardStore

    /// Where every local store lives, kept because tab-to-complete opens its corpus after launch.
    private let container: URL
    private let onboardingRecordStore: any OnboardingRecordStore
    private let clipboardPreferencesFile: ClipboardPreferencesFile
    /// The speech model's last loads, kept across launches for the Diagnostics page.
    private let speechModelLoadLog: SpeechModelLoadLog
    private var clipboardPreferences = ClipboardPreferences()
    private var clipboardPreferencesUnreadable = false
    private var clipboardPreferencesSetAside: URL?
    private var clipboardPauseTask: Task<Void, Never>?
    private var clipboardPauseUntil: Date?
    private var retentionSweepTask: Task<Void, Never>?

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
    /// Makes a released model reloadable by its next query without fetching weights now.
    private let allowModelReload: (@Sendable () async -> Void)?
    /// Waits out calm so a test can advance the pressure timer without wall-clock delay.
    private let waitForCalm: @Sendable (Duration) async throws -> Void
    private let pasteboardOverride: (any UttrflowInput.Pasteboard)?
    /// Asks which clean-up engines can run, held as a seam so availability changes are testable.
    private let transformerReadiness: @Sendable (UserProfile) async -> Set<TransformerKind>
    /// Whether the weights have been asked for and not let go since, so turning the feature on twice does not ask twice.
    private var isModelPreparing = false
    /// Counts each ask and each release, so a load that lands after the feature was turned off reports nothing.
    private var modelAsk = 0
    /// The latest fetch of those weights, internal so a test can wait for it rather than for the clock.
    private(set) var modelPreparation: Task<Void, Never>?
    /// When the suggestion model gives memory back and takes it again; internal so a test can shorten the waits.
    var memoryPressure = ModelMemoryPressure()
    /// When the speech model gives memory back and may give it back again; internal so a test can drive it.
    var speechPressure = ModelMemoryPressure()
    /// The reload waiting for memory to stay calm, cancelled by the next reading; internal so a test can wait for it.
    private(set) var pressureReload: Task<Void, Never>?
    private let pressureSource = MemoryPressureSource()
    /// Which clean-up engines answered that they could run; internal so a test can read it back.
    private(set) var transformerAvailability: [TransformerKind: Bool] = [:]
    /// Whether the first rules-only fallback due to Apple Intelligence has already been explained.
    private var appleIntelligenceFallbackNoticeShown = false
    /// Prevents a slower earlier probe from replacing a newer reading.
    private var transformerProbeGeneration = 0
    /// The clean-up engine that produced the last inserted dictation.
    private(set) var lastCleanedBy: TransformerKind?
    /// What the store last said about the speech model on disk; internal so a test can read it.
    private(set) var speechModelPresence: DiagnosticsModelPresence?

    /// How far along that fetch is; internal so a test can read back what it did.
    private(set) var suggestionModel: SuggestionModelReadiness = .notAsked {
        didSet {
            guard suggestionModel != oldValue else { return }
            settingsPage.setSuggestionModel(suggestionModel)
            refreshMenuBar()
        }
    }
    private var suggestionSecureInputNotice: String?
    private var suggestionRuntime: SuggestionRuntimeStatus = .idle {
        didSet {
            settingsPage.setSuggestionRuntime(suggestionRuntime)
            refreshMenuBar()
        }
    }

    /// Builds the app around one folder, which a test points at a temporary one.
    init(
        container: URL = .applicationSupportDirectory, loginItem: LaunchAtLogin = LaunchAtLogin(),
        settingsStore: UserDefaultsSettingsStore = UserDefaultsSettingsStore(),
        onboardingRecordStore: any OnboardingRecordStore = UserDefaultsOnboardingRecordStore(),
        account: OnboardingAccountLayer = .forThisBuild(),
        scoring: (any CandidateScoring)? = nil, generating: (any CandidateGenerating)? = nil,
        prepareModel: (@Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void)? = nil,
        releaseModel: (@Sendable () async -> Void)? = nil,
        allowModelReload: (@Sendable () async -> Void)? = nil,
        encryptedStore: EncryptedStore? = nil,
        localTidier: (any CleanupModel)? = nil,
        waitForCalm: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        transformerReadiness: @escaping @Sendable (UserProfile) async -> Set<TransformerKind> = {
            profile in await SettingsCapabilities.refreshed(for: profile).readyTransformers
        }, pasteboard: (any UttrflowInput.Pasteboard)? = nil,
        secureInput: SecureInputWatch = SecureInputWatch()
    ) {
        self.container = container
        self.secureInput = secureInput
        self.onboardingRecordStore = onboardingRecordStore
        self.encryptedStore = encryptedStore
        self.localTidier = localTidier
        clipboardPreferencesFile = ClipboardPreferencesFile(
            path: ClipboardPreferencesFile.defaultFile(in: container).path)
        speechModelLoadLog = SpeechModelLoadLog(file: SpeechModelLoadLog.defaultFile(in: container))
        switch clipboardPreferencesFile.load() {
        case .missing:
            clipboardPreferences = ClipboardPreferences()
        case .read(let preferences):
            clipboardPreferences = preferences
        case .recovered(let preferences, _, _, _, _):
            clipboardPreferences = preferences
        case .unsupportedVersion:
            clipboardPreferences = ClipboardPreferences()
            clipboardPreferencesUnreadable = true
        case .unreadable(let setAside):
            clipboardPreferences = ClipboardPreferences()
            clipboardPreferencesUnreadable = true
            clipboardPreferencesSetAside = setAside
        }
        clipboardPauseUntil = clipboardPreferences.pausedUntil
        self.loginItem = loginItem
        self.settingsStore = settingsStore
        self.account = account
        self.scoring = scoring
        self.generating = generating
        self.prepareModel = prepareModel
        self.releaseModel = releaseModel
        self.allowModelReload = allowModelReload
        self.waitForCalm = waitForCalm
        self.transformerReadiness = transformerReadiness
        pasteboardOverride = pasteboard
        history = DictationHistoryStore(
            file: DictationHistoryStore.defaultFile(in: container), encryptedStore: encryptedStore)
        recordings = RecordingStore(
            directory: RecordingStore.defaultDirectory(in: container), encryptedStore: encryptedStore)
        let evidence = encryptedStore.map {
            EvidenceLedgerStore(file: EvidenceLedgerStore.defaultFile(in: container), encryptedStore: $0)
        }
        dictionary = PersonalDictionaryStore(
            file: PersonalDictionaryStore.defaultFile(in: container), encryptedStore: encryptedStore,
            sightings: evidence.flatMap { ledger in
                encryptedStore.map { store in
                    SightingMemory(ledger: ledger, encryptedStore: store) { [settingsStore] now in
                        RetentionWindow(days: settingsStore.load().transcriptRetentionDays, now: now)
                    }
                }
            })
        snippets = SnippetStore(file: SnippetStore.defaultFile(in: container), encryptedStore: encryptedStore)
        clipboard = ClipboardStore(
            file: ClipboardStore.defaultFile(in: container), encryptedStore: encryptedStore)
        self.evidence = evidence
        super.init()
        if clipboardPreferencesUnreadable {
            actionNotice = Self.clipboardPreferencesUnreadableNotice(
                canRestore: clipboardPreferencesSetAside != nil)
        }
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
    private var lastTranscriptGeneration = 0
    /// The newest history write, awaited before the last transcript is checked against history.
    private var historyWrite: Task<Void, Never>?
    /// Asked when the panel opens whether a paste can be placed, held so the answer costs one call.
    private let accessibility = AccessibilityPermissionGate()
    private let microphone = MicrophonePermissionGate()
    private let focus: any AccessibilityFocus = AXAccessibilityFocus()
    /// D5 — asked, when the panel opens, which languages have a formatter on this disk.
    private let formatter: any CodeFormatting = SystemCodeFormatter()

    /// The one pasteboard that announces its writes, so no inserter can silently forget to. See `Docs/insertion.md`.
    private lazy var announcingPasteboard: any UttrflowInput.Pasteboard =
        pasteboardOverride
        ?? SystemPasteboard(
            willWrite: { [clipboardWatcher] in clipboardWatcher.ignoreNextWrite(of: $0) },
            willWritePicture: { [clipboardWatcher] in clipboardWatcher.ignoreNextPicture($0) })

    /// Puts a chosen clip where the caret is, announcing the write so it is not read as a copy.
    lazy var clipInserter: any TextInserting = TextInsertion.coordinator(
        pasteboard: announcingPasteboard)

    /// Replays the last transcript through the clipboard-free dictation route.
    var lastTranscriptInserter: any TextInserting = TextInsertion.dictation()

    /// Panel pastes do not read another app's text field just to decide whether to show a notice.
    private lazy var panelClipInserter: any TextInserting = TextInsertion.coordinator(
        pasteboard: announcingPasteboard, confirmsArrival: false, clipboardFallback: false)

    /// The same for a secret clip, whose words reach the clipboard only with the concealed marker.
    private lazy var secretInserter = TextInsertion.coordinator(
        pasteboard: ConcealingPasteboard(announcingPasteboard))

    /// The panel's concealed route follows the same no-confirmation rule as ordinary clips.
    private lazy var panelSecretInserter = TextInsertion.coordinator(
        pasteboard: ConcealingPasteboard(announcingPasteboard), confirmsArrival: false,
        clipboardFallback: false)

    /// The panel's state while it is open, held here so tests can inspect the notice it produces.
    private(set) var panel: PanelSnapshot?
    private var panelTarget: InsertionDestination?
    /// Counts Format presses, so only the latest run's result may open its sheet.
    private var formatterRuns = 0
    /// Counts the store reads the panel has asked for, so an older list never replaces a newer one.
    private var panelReads = 0
    private var clipboardWatchTask: Task<Void, Never>?

    /// F7, F9 — the clip a delete removed, held by the app because the undo outlives the panel.
    var undoOffer = PanelUndoOffer()
    var undoTask: Task<Void, Never>?
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
            elsewhere: keptElsewhere(), running: { [weak self] in self?.completions },
            encryptedStore: encryptedStore, evidence: evidence),
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
    /// The order each page's list is read in, kept per page so choosing one never reorders another.
    private var sorts: [MainTab: String] = [:]

    /// How long a finished result stays up, so the last dictation does not sit over every app.
    static let successLingers = Duration.seconds(2)
    /// Longer, because a failure asks something of the user — but it still goes.
    static let failureLingers = Duration.seconds(10)
    static let voiceOverFailureLingers = Duration.seconds(20)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before the first read, so an install onboarded under ⌥Space keeps it. See `Docs/shortcuts.md`.
        settingsStore.pinDefaults(onboarded: onboardingRecordStore.hasFinished)
        settings = settingsStore.load()
        // Reconciled at launch too: the login item can be removed without telling the app.
        applyAppearance()
        _ = BrandFont.isAvailable
        InstalledApplicationName.install()
        applyLaunchAtLogin()
        startTelemetry()
        crashReports.follow(isEnabled: settings.sendsCrashReports)
        buildPipeline()
        Task { await restoreLastTranscript() }
        wireInterface()
        CGEventKeystrokeSender.startObservingLayout()
        startWatchingForTheShortcut()
        accessibilityTrust.start()
        startWatchingTheClipboard()
        startCompletingWhatIsTyped()
        pressureSource.start { [weak self] in self?.memoryPressureChanged(to: $0) }
        loadSpeechModel()
        // A Mac that worked without an account keeps no trace of it, and meets sign-in like anyone signed out.
        RetiredLocalAccount.forget()
        // Everything above armed itself only with a session; this records which state that was.
        appliedSession = isSignedIn
        refreshMenuBar()
        presentOnboardingIfNeeded(behavior: .developmentLaunch)
        // Shown at launch, since a menu-bar icon alone is an interface most people never find.
        if onboarding == nil {
            show(.main(.home))
        } else {
            refreshMainWindow()
        }
        // These launch tasks do not feed the first window, so let it appear before starting the work.
        migrateDictionarySpellings()
        seedTheDictionary()
        sweepExpired()
        startPeriodicRetentionSweep()
        probeTransformers()
        probeSpeechModel()
        refreshAccount()
        // Configured last, from the setting; the automatic check itself waits for `modelLoadingSettled()`.
        updates.onProgressChanged = { [weak self] in self?.refreshMenuBar() }
        updates.begin(
            checksAutomatically: settings.checksForUpdatesAutomatically,
            installsAutomatically: settings.installsUpdatesAutomatically)
    }

    /// Respells legacy dictionary entries before seeding or serving the dictionary.
    private func migrateDictionarySpellings() {
        dictionaryMigrationWork = Task(priority: .utility) { [weak self, dictionary] in
            guard let self else { return }
            do throws(DictionaryStoreError) {
                let changes = try await dictionary.respellInLatinScript()
                guard !changes.isEmpty else { return }
                let example =
                    changes.first.map {
                        " For example, “\($0.before.word)” is now “\($0.after.word)”."
                    } ?? ""
                actionNotice = MainNotice(
                    message:
                        "Updated \(changes.count) dictionary \(changes.count == 1 ? "spelling" : "spellings") to Latin letters.\(example)",
                    symbolName: "character.book.closed.fill", tone: .neutral)
                announce("Updated dictionary spellings to Latin letters.", urgently: false)
                refreshMainWindow()
            } catch {
                Self.log.error(
                    "dictionary respelling failed: \(SuggestionLog.failure(error), privacy: .public)")
            }
        }
    }

    /// Builds the telemetry service from the saved switch and starts its hourly flush.
    private func startTelemetry() {
        let usage = UsageTelemetry(
            isEnabled: settings.sharesUsageStatistics, sender: account.telemetry,
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        usage.start()
        telemetry = usage
    }

    /// Deletes recordings, transcripts and clipboard clips past their retention, with or without a window.
    func sweepExpired(now: Date = Date()) {
        let retention = Retention(days: settings.transcriptRetentionDays, now: now)
        let clipboardRetention = ClipRetention(
            days: settings.clipboardRetentionDays, now: now,
            dictationDays: settings.transcriptRetentionDays)
        let previous = sweeping
        let overrides = settings.destinations
        sweeping = Task(priority: .utility) { [recordings, history, clipboard, evidence, dictionary] in
            await previous?.value
            _ = await recordings.waiting(now: now)
            let records = await history.records(keeping: retention)
            await EvidenceSources.backfill(
                evidence, from: records, dictionary: dictionary, overrides: overrides,
                keeping: RetentionWindow(days: retention.days, now: now))
            _ = await clipboard.clips(keeping: clipboardRetention)
        }
    }

    /// Catches clips that age out while Uttrflow is idle, without doing store I/O on the main thread.
    private func startPeriodicRetentionSweep() {
        guard retentionSweepTask == nil else { return }
        retentionSweepTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3_600)) } catch { return }
                guard let self else { return }
                sweepExpired()
            }
        }
    }

    /// Writes the words this build ships knowing, which happens once and never blocks the launch.
    private func seedTheDictionary() {
        let migration = dictionaryMigrationWork
        Task(priority: .utility) { [dictionary, migration] in
            await migration?.value
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
        running: @escaping @Sendable @MainActor () -> SuggestionCoordinator? = { nil },
        encryptedStore: EncryptedStore? = nil, evidence: EvidenceLedgerStore? = nil
    ) -> FilePersonalisationStore {
        FilePersonalisationStore(
            dictionary: dictionary, history: history, clipboard: clipboard,
            suggestions: PredictCorpus(
                container: container, running: running, encryptedStore: encryptedStore),
            met: { AppDelegate.applicationsTheLoopHasMet(in: container) },
            elsewhere: elsewhere, ledger: .shared, evidence: evidence,
            storage: { LocalStoreInventory.usage(in: container) })
    }

    /// Applications the completion loop has met, so the Suggestions list can offer a switch for each.
    nonisolated static func applicationsTheLoopHasMet(in container: URL) -> Set<String> {
        let file = CapturePreferencesFile(
            path: CapturePreferencesFile.defaultFile(in: container).path(percentEncoded: false))
        return Set(file.load().consent.keys)
    }

    /// The files a full reset reaches that the settings module has no store for.
    private func keptElsewhere() -> KeptElsewhere {
        let encryptedStore = self.encryptedStore
        return KeptElsewhere(
            recordings: { [recordings] in try await recordings.discardEverything() },
            snippets: { [snippets] in try await snippets.deleteEverything() },
            suggestionConsent: { [weak self] in try await self?.forgetEveryConsentAnswer() },
            revokeEncryptionKey: {
                guard let encryptedStore else { return }
                try encryptedStore.revokeKey()
            })
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
            speechLoadFailure = await pipeline.lastLoadFailure
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
            download: speechReadiness.download, stopGesture: recordingStopGesture,
            heardSoFar: heardSoFar, waited: waitStarted.map { $0.duration(to: .now) } ?? .zero)
    }

    /// Asks each clean-up engine whether it could run, so Diagnostics has an answer to show; the task ends once it has.
    @discardableResult
    func probeTransformers() -> Task<Void, Never> {
        transformerProbeGeneration += 1
        let generation = transformerProbeGeneration
        return Task(priority: .utility) { [weak self] in
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
        return Task(priority: .utility) { [weak self] in
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
        Task(priority: .utility) { [account] in
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
        observeDictationSessionEnd()
    }

    /// Closes every window and panel, stops listening, and leaves sign-in as the one thing on screen.
    private func closeForSignedOut() {
        removeDictationSessionObservers()
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
    private func presentOnboardingIfNeeded(behavior: OnboardingPresentationBehavior = .standard) {
        let signedIn = isSignedIn
        guard
            !signedIn
                || OnboardingWindowController(
                    settingsStore: settingsStore, installer: speechInstall, account: account
                ).isRequired
        else { return }
        presentOnboarding(behavior: signedIn ? .standard : behavior)
    }

    /// Brings forward the flow already open, else builds a fresh one so a finished flow never reopens on its last page.
    private func presentOnboarding(behavior: OnboardingPresentationBehavior = .standard) {
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
        onboarding.onSignIn = { [weak self, weak onboarding] in
            guard let self else { return }
            followSession()
            if behavior == .developmentLaunch { onboarding?.closeIfNotRequired() }
        }
        onboarding.onSettingsChange = { [weak self] in self?.settingsChanged(to: $0) }
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
            // Cleared here too, so a window shut with the red button never holds updates back.
            if self.onboarding === onboarding { self.onboarding = nil }
            updates.refresh()
            refreshMainWindow()
            loadSpeechModelIfItArrived()
        }
        if behavior == .developmentLaunch { onboarding.signInAsStandInIfNeeded() }
        onboarding.present()
    }

    /// How long quitting waits for a dictation to land. See `Docs/quitting.md`.
    private static let quitBudget = Duration.seconds(15)

    /// Finishes the dictation in flight before letting the process die, but not for ever.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        completions?.stop()
        let watchingClipboard = settings.clipboardEnabled && !isClipboardPaused
        let arrived: @Sendable (NoticedClip) async -> Void = { [weak self] noticed in
            await self?.clipArrived(noticed)
        }
        Task { [weak self, pipeline, clipboard, clipboardWatcher, telemetry] in
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
                catchUpClipboard: {
                    guard watchingClipboard else { return }
                    await clipboardWatcher.catchUp(handing: arrived)
                },
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
        heardTask?.cancel()
        dismissalTask?.cancel()
        completions?.stop()
        pressureSource.stop()
        removeDictationSessionObservers()
    }

    private func observeDictationSessionEnd() {
        guard dictationSessionObservers.isEmpty else { return }
        dictationSessionObservers = DictationSessionEndObserver.observe(
            in: NSWorkspace.shared.notificationCenter
        ) { [weak self] in
            Task { @MainActor in await self?.queueDictationSessionEnd() }
        }
        screenLockObserver = DictationSessionEndObserver.observeScreenLock(
            in: DistributedNotificationCenter.default()
        ) { [weak self] in
            Task { @MainActor in await self?.queueDictationSessionEnd() }
        }
    }

    private func removeDictationSessionObservers() {
        for observer in dictationSessionObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        dictationSessionObservers.removeAll()
        if let screenLockObserver {
            DistributedNotificationCenter.default().removeObserver(screenLockObserver)
            self.screenLockObserver = nil
        }
    }

    private func queueDictationSessionEnd() async {
        await controller?.endForSessionEnding()
        closeQuickPanel()
    }

    /// Builds tab-to-complete, or leaves it unbuilt, which is what everybody who has not asked for it gets.
    private func startCompletingWhatIsTyped() {
        guard surfaces.completesWhatIsTyped, completions == nil else { return }
        prepareTheModelIfNeeded()
        let tapFailureStatus: (any Error) -> SuggestionRuntimeStatus = { error in
            if let failure = error as? KeyInterceptorFailure, failure == .accessibilityDenied {
                return .accessibilityDenied
            }
            return .tapFailed
        }
        do {
            let coordinator = try SuggestionCoordinator(
                container: container, preferences: settings.suggestions, scoring: scoring,
                generating: generating, encryptedStore: encryptedStore,
                editHeard: { [weak self] edit in
                    await MainActor.run {
                        guard let self, let evidence = self.evidence else { return }
                        self.noteEvidence(
                            EvidenceSources.pair(kept: edit, day: EvidenceRow.day(of: Date())), in: evidence)
                    }
                })
            // ⌥⎋ persists the master switch off, so the screen agrees and turning it back on rebuilds the loop.
            coordinator.onTurnedOffEverywhere = { [weak self] in
                self?.apply(.toggle(.suggestionsEnabled, isOn: false))
            }
            coordinator.onSecureInputBlockingChanged = { [weak self] isBlocking in
                self?.suggestionSecureInputNotice = isBlocking ? SecureInputWatch.suggestionNotice : nil
                self?.refreshMenuBar()
            }
            coordinator.onTapRestChanged = { [weak self] result in
                guard let self else { return }
                guard let result else {
                    suggestionRuntime = .tapResting
                    refreshMenuBar()
                    return
                }
                switch result {
                case .success:
                    suggestionRuntime =
                        coordinator.isSecureInputBlocking ? .secureInputBlocked : .running
                case .failure(let error): suggestionRuntime = tapFailureStatus(error)
                }
                refreshMenuBar()
            }
            coordinator.onTapRestRestarting = { [weak self] in
                guard let self else { return }
                suggestionRuntime = .restarting
                refreshMenuBar()
            }
            coordinator.onSecureInputChanged = { [weak self] isBlocking in
                self?.suggestionRuntime = isBlocking ? .secureInputBlocked : .running
            }
            completions = coordinator
            suggestionRuntime = .starting
            switch coordinator.start() {
            case .success:
                if coordinator.tapRest.isPending {
                    suggestionRuntime = .starting
                } else if suggestionRuntime != .secureInputBlocked {
                    suggestionRuntime = .running
                }
            case .failure(let error):
                suggestionRuntime = tapFailureStatus(error)
            }
        } catch {
            Self.log.error("the corpus would not open: \(SuggestionLog.failure(error), privacy: .public)")
            suggestionRuntime = .corpusFailed
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
                self?.suggestionModel = self?.suggestionModel == .loading ? .loadFailed : .fetchFailed
            }
        }
    }

    /// Says the weights must be fetched again, after a reload found them gone from disk and did not fetch them itself.
    func suggestionModelWentMissing() {
        guard settings.suggestions.isEnabled, isModelPreparing else { return }
        // Cleared, so turning the switch off and on fetches them, as it does after any failed fetch.
        isModelPreparing = false
        suggestionModel = .fetchFailed
    }

    /// Lets the weights go once the feature is off, stopping any load still in flight. See `Docs/performance-suggestions.md`.
    private func releaseTheModel() {
        guard isModelPreparing || suggestionModel == .fetchFailed || suggestionModel == .loadFailed
        else { return }
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

    /// Lets the recogniser go under pressure when idle, at a warning only once the last reload has held. See `Docs/performance.md`.
    private func releaseSpeechModelIfIdle(at level: MemoryPressureLevel) {
        guard case .idle = lastDictationState, let speechEngine else { return }
        guard level == .critical || speechPressure.allowsRelease(at: .now) else { return }
        speechPressure.released(at: .now)
        Task { await speechEngine.release() }
    }

    /// Releases the suggestion model under pressure, then permits a query-driven reload after calm. See `Docs/performance-suggestions.md`.
    func memoryPressureChanged(to level: MemoryPressureLevel) {
        switch level {
        case .warning, .critical:
            PanelThumbnails.shared.releaseForMemoryPressure()
            pressureReload?.cancel()
            pressureReload = nil
            releaseSpeechModelIfIdle(at: level)
            guard settings.suggestions.isEnabled, isModelPreparing else { return }
            memoryPressure.released(at: .now)
            releaseTheModel()
            suggestionModel = .releasedForMemory
        case .normal:
            // A repeated calm keeps the countdown already running.
            guard memoryPressure.isReleased, pressureReload == nil,
                let allowModelReload
            else { return }
            let wait = memoryPressure.wait
            let waitForCalm = waitForCalm
            pressureReload = Task { [weak self] in
                try? await waitForCalm(wait)
                guard !Task.isCancelled, let self, memoryPressure.isReleased,
                    settings.suggestions.isEnabled
                else { return }
                await allowModelReload()
                guard !Task.isCancelled, memoryPressure.isReleased,
                    settings.suggestions.isEnabled
                else { return }
                isModelPreparing = true
            }
        }
    }

    /// Shows the model as getting ready while an idle reload runs, then as ready or failed by how it ends.
    func suggestionModelReloaded(_ event: IdleReload) {
        guard isModelPreparing else { return }
        switch event {
        case .started:
            if memoryPressure.isReleased { memoryPressure.reloaded(at: .now) }
            if suggestionModel == .ready || suggestionModel == .releasedForMemory {
                suggestionModel = .loading
            }
        case .finished where suggestionModel == .loading:
            suggestionModel = .ready
        case .failed where suggestionModel == .loading:
            // Cleared so that turning the feature off and on loads the model again.
            isModelPreparing = false
            suggestionModel = .loadFailed
        case .finished, .failed:
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
        suggestionRuntime = .idle
        completions?.stop()
        completions = nil
        memoryPressure.forget()
        pressureReload?.cancel()
        pressureReload = nil
        releaseTheModel()
    }

    /// Arms the shortcut again when it could not be armed before. See `Docs/shortcuts.md`.
    func applicationDidBecomeActive(_ notification: Notification) {
        synchronizeLaunchAtLoginWithSystem()
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
            spellings: { [dictionary] in await dictionary.index() }, localModel: localTidier,
            outcomes: diagnostics)
    }

    /// The recogniser of `kind`, over the downloaded model.
    private func makeSpeechEngine(_ kind: SpeechEngineKind) -> any SpeechEngine {
        let model = SpeechModel.default
        let engine = SpeechEngineFactory.make(
            kind: kind, model: model, modelFolder: modelStore.location(of: model),
            loadLog: speechModelLoadLog,
            didRelease: { [weak self] in
                Task { @MainActor [weak self] in self?.speechModelWasReleased() }
            },
            didLoad: { [weak self] in
                Task { @MainActor [weak self] in self?.speechModelWasLoaded() }
            },
            willLoad: { [weak self] in
                Task { @MainActor [weak self] in self?.speechModelWillLoad() }
            })
        speechEngine = engine
        return engine
    }

    /// The idle watcher released a recogniser that the readiness surfaces still called ready.
    private func speechModelWasReleased() {
        guard speechReadiness == .ready else { return }
        speechReadiness = .loading
        speechLoadStarted = nil
        Task { await pipeline?.speechWasReleased() }
        refreshSpeechModelSurfaces()
    }

    /// A cold reload finished, including one started lazily when the user began dictating.
    private func speechModelWasLoaded() {
        Task { await pipeline?.speechWasLoaded() }
        guard speechReadiness == .loading else { return }
        speechReadiness = .ready
        speechLoadStarted = nil
        speechLoadTicker?.cancel()
        speechLoadTicker = nil
        refreshSpeechModelSurfaces()
    }

    /// Starts the elapsed-time indicator when a released model actually begins reloading.
    private func speechModelWillLoad() {
        guard speechReadiness == .loading, speechLoadStarted == nil else { return }
        speechLoadStarted = .now
        speechLoadTicker?.cancel()
        speechLoadTicker = Task { [weak self] in
            try? await Task.sleep(for: SpeechModelLoad.estimateAfter)
            while !Task.isCancelled {
                guard let self, speechReadiness == .loading else { return }
                refreshSpeechModelEstimate()
                try? await Task.sleep(for: SpeechModelLoadEstimate.redrawInterval)
            }
        }
        refreshSpeechModelSurfaces()
    }

    private func buildPipeline() {
        let speech = makeSpeechEngine(settings.engines.speech)
        speechInUse = speech.kind

        // The ledger is read only while the persona layer is on, and only inside History's window.
        var personaEvidence: (@Sendable () async -> [EvidenceRow])?
        if qualityLayers.isOn(.personaVocabulary), let ledger = evidence {
            let days = settings.transcriptRetentionDays
            personaEvidence = { await ledger.rows(keeping: RetentionWindow(days: days, now: Date())) }
        }
        // Pairings the user kept or undid steer the correction gate whenever there is a ledger to read them from.
        let pairDays = settings.transcriptRetentionDays
        let pairLedger = evidence
        let pairing: DictionaryCorrections.Pairing = { @Sendable in
            guard let pairLedger else { return [:] }
            return ConfusionPairs.project(
                await pairLedger.rows(keeping: RetentionWindow(days: pairDays, now: Date())))
        }
        // Ranked against the screen the pipeline already read for this dictation, not a second read of its own.
        let speechWords = DictionaryVocabulary(evidence: personaEvidence) { [dictionary] in
            await (dictionary.allEntries(), dictionary.index(), Date())
        }

        // One cue for both ends, shaped when it can be and the plain system sound when it cannot.
        let sounds = RecordingSounds(
            player: FallbackSoundPlayer([ShapedSoundPlayer(), SystemSoundPlayer()]),
            enabled: settings.playsSoundWhenRecordingStarts)
        recordingSounds = sounds
        let cue = sounds.cue
        let reportWarning = DictationWarningReporter(cue: cue) { [weak self] announcement in
            Task { @MainActor in self?.announce(announcement) }
        }

        // Held so the floating button's meter reads the level without queueing behind a `stop()`.
        let chosenMicrophone = chosenMicrophone
        chosenMicrophone.apply(settings)
        let microphone = AVAudioCaptureEngine(
            source: AVAudioEngineMicrophoneSource(preferredUID: { chosenMicrophone.current }),
            recordings: recordings, cue: cue)
        dock.setLevelSource { microphone.momentaryLevel }
        dock.onInputSilent = { [weak self] in self?.announce(InputSilence.line, urgently: false) }

        // Where each dictation landed, so "delete that" under the command key can find it. See `Docs/commands.md`.
        let ledger = InsertionLedger()
        let pipeline = DictationPipeline(
            capture: microphone,
            speech: speech,
            cleaner: cleaner(for: settings),
            context: context,
            // Announced, like every write this app makes. See `Docs/insertion.md`.
            inserter: TextInsertion.dictation(ledger: ledger),
            speechWords: { seeing in await speechWords.vocabulary(favouring: seeing) },
            corrector: DictionaryCorrections(
                index: { [dictionary] in await dictionary.index() }, pairs: pairing),
            snippets: StoredSnippets(store: snippets),
            learner: StoreCounters(
                dictionary: dictionary, snippets: snippets,
                noteUses: { [weak self] used in
                    await MainActor.run {
                        guard let self, let evidence = self.evidence else { return }
                        self.noteEvidence(
                            EvidenceSources.uses(of: used, day: EvidenceRow.day(of: Date())), in: evidence)
                    }
                },
                // Detached from the pipeline, so its wait for a hand edit never holds the next dictation.
                watchEdits: { [dictionary] applied, inserted in
                    Task { await EditAwayWatch(dictionary: dictionary).watch(applied, inserted: inserted) }
                }),
            vocabulary: LearnedVocabulary(
                dictionary: dictionary,
                didLearn: { [weak self] entries in
                    await MainActor.run { self?.noteLearned(entries) }
                },
                // Lines from apps typing capture may read, behind the same consent gate as the pipeline.
                typedLines: { [weak self] context in
                    guard let bundle = context.bundleIdentifier,
                        let loop = await MainActor.run(body: { self?.completions })
                    else { return [] }
                    return await loop.typedLines(in: bundle)
                }),
            spellings: { [personaEvidence] in await SpellingPreferences.project(personaEvidence?() ?? []) },
            // The same answers typing capture keeps, so one refusal covers both. See `Docs/predict.md`.
            consent: CapturePreferencesFile(
                path: CapturePreferencesFile.defaultFile(in: container).path(percentEncoded: false)),
            metrics: telemetry.map { MetricsFanOut([diagnostics, $0.recorder]) } ?? diagnostics,
            cleaningRecorder: diagnostics,
            destinationOverrides: settings.destinations,
            recordings: recordings,
            // A retry runs with Uttrflow's own window in front, so its words can only be copied.
            clipboard: TextInsertionCoordinator(strategies: [
                ClipboardTextInsertionEngine(
                    pasteboard: announcingPasteboard,
                    secretClassifier: { ClipKindDetector.kind(of: $0) == .secret })
            ]),
            profile: settings.profile,
            commands: EditCommandRegistry([
                RecordedEditCommand(ledger: ledger), KeyEditCommand(overrides: settings.destinations),
                MarkdownEditCommand(),
            ]),
            layers: qualityLayers
        )
        self.pipeline = pipeline

        controller = DictationController(
            pipeline: pipeline,
            monitor: ActivationMonitor(),
            commandMonitor: ActivationMonitor(),
            cue: cue,
            activation: settings.hotkeyActivation,
            handsFreeEnabled: settings.handsFreeEnabled,
            doubleTapWindow: .milliseconds(settings.handsFreeDoubleTapMilliseconds),
            minimumHold: .milliseconds(settings.handsFreeHoldMilliseconds),
            clock: ContinuousClock(),
            onAdvice: { [weak self] advice in
                Task { @MainActor in self?.recordingAdviceChanged(to: advice) }
            },
            onWarning: reportWarning.report,
            onNearMissTap: { [weak self] in
                Task { @MainActor in self?.announce(DictationPresenter.nearMissTapAnnouncement) }
            },
            onStopGestureChange: { [weak self] gesture in
                Task { @MainActor in self?.recordingStopGestureChanged(to: gesture) }
            }
        )
        DictationIntentBridge.run = { [weak self] command in
            await self?.controller?.command(command) ?? .nothingRecording
        }
    }

    /// Redraws the menu bar and the floating button as a recording nears its cap.
    private func recordingAdviceChanged(to advice: DictationAdvice) {
        guard advice != recordingAdvice else { return }
        recordingAdvice = advice
        refreshMenuBar()
        dock.update(with: dockPresentation(for: lastDictationState))
    }

    /// Redraws the floating button as each piece of a held recording is finished.
    private func heardSoFarChanged(to words: String?) {
        guard words != heardSoFar else { return }
        heardSoFar = words
        dock.update(with: dockPresentation(for: lastDictationState))
    }

    /// Redraws the menu and the floating button when the gesture that ends a recording has changed.
    private func recordingStopGestureChanged(to gesture: StopGesture) {
        guard gesture != recordingStopGesture else { return }
        recordingStopGesture = gesture
        refreshMenuBar()
        dock.update(with: dockPresentation(for: lastDictationState))
    }

    private func wireInterface() {
        guard let pipeline else { return }

        updateSuggestionApplicationContext()
        menuBar.onCommand = { [weak self] intent in self?.carryOut(intent) }
        menuBar.onMenuWillOpen = { [weak self] in
            self?.checkSecureInput()
            self?.refreshMenuBar()
            self?.refreshMenuClips()
        }
        secureInputObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateSuggestionApplicationContext()
                self?.checkSecureInput()
                self?.refreshMenuBar()
            }
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
        dock.onAttentionChange = { [weak self] isAttended in
            self?.dockAttentionChanged(to: isAttended)
        }

        dock.setShortcut(SettingsShortcut.compact(settings.hotkey))
        dock.setShrinksToGrip(settings.shrinksToGripWhenIdle)
        checkSecureInput()
        showTheFloatingButtonIfWanted()

        stateTask = Task { [weak self] in
            for await state in await pipeline.states() {
                self?.render(state)
            }
        }
        heardTask = Task { [weak self] in
            for await words in await pipeline.wordsHeardSoFar() {
                self?.heardSoFarChanged(to: words)
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
    private var shortcutArmingAttempt = 0
    private lazy var shortcutArming = ShortcutArming(
        onChange: { [weak self] in self?.showShortcutUnheard() },
        accessibilityIsGranted: { AXIsProcessTrusted() })
    /// Claimed shortcuts the window server refused, each with its refusal, so a row says why.
    private var unarmedShortcuts: [ShortcutAction: HotkeyError] = [:] {
        didSet {
            guard unarmedShortcuts != oldValue else { return }
            showRefusedShortcuts()
        }
    }

    /// Every shortcut not armed, Dictate included, on the one settings seam that says why.
    private func showRefusedShortcuts() {
        var refused = unarmedShortcuts
        refused[.dictate] = shortcutArming.failure
        settingsPage.setUnarmedShortcuts(refused)
    }

    /// Arms the dictation shortcut while dictation is on, and releases it while it is off.
    private func startWatchingForTheShortcut() {
        shortcutArmingAttempt += 1
        let attempt = shortcutArmingAttempt
        guard let controller else { return }
        guard surfaces.listensForDictation else {
            shortcutArming.disarm()
            Task { await controller.stop() }
            return
        }
        let binding = settings.hotkey
        let commandBinding = settings.shortcuts.first(for: .editCommand)
        let arming = shortcutArming
        // Kept as its own state on the menu bar and floating button, never shown as a failed dictation.
        Task {
            await arming.arm { () throws(HotkeyError) in
                guard attempt == self.shortcutArmingAttempt, self.surfaces.listensForDictation else { return }
                try await controller.start(binding: binding)
            }
            if let failure = arming.failure {
                let reason = SuggestionLog.failure(failure)
                Self.log.error("the dictation shortcut is not armed: \(reason, privacy: .public)")
            }
            guard attempt == self.shortcutArmingAttempt, arming.failure == nil else { return }
            do throws(HotkeyError) {
                try await controller.start(commandBinding: commandBinding)
            } catch {
                let reason = error.userMessage
                Self.log.error("the edit-command shortcut is not armed: \(reason, privacy: .public)")
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
        settingsPage.setClipboardCapturePaused(isClipboardPaused)
        if isClipboardPaused { startClipboardPauseTimerIfNeeded() }
        guard surfaces.watchesTheClipboard, !isClipboardPaused else {
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
        let excludedApplications = clipboardPreferences.excludedBundleIdentifiers
        // Utility, because a poll nobody is waiting on should not run as the main thread's work.
        clipboardWatchTask = Task(priority: .utility) { [clipboardWatcher] in
            // Whatever was copied while the switch was off stays unrecorded.
            await clipboardWatcher.passOver(upTo: baseline)
            await clipboardWatcher.setExcludedApplications(excludedApplications)
            await clipboardWatcher.run(
                handing: arrived,
                whenCaptureDegrades: { [weak self] in await self?.reportClipboardCaptureDegraded() })
        }
    }

    var isClipboardPaused: Bool {
        guard !clipboardPreferencesUnreadable else { return true }
        guard let clipboardPauseUntil else { return false }
        return clipboardPauseUntil > Date()
    }

    /// Stops capture immediately and resumes from a fresh baseline after one hour.
    private func setClipboardPaused(_ isPaused: Bool) {
        guard !clipboardPreferencesUnreadable else { return }
        clipboardPauseTask?.cancel()
        clipboardPauseTask = nil
        clipboardPauseUntil = isPaused ? Date().addingTimeInterval(60 * 60) : nil
        clipboardPreferences.pausedUntil = clipboardPauseUntil
        settingsPage.setClipboardCapturePaused(isPaused)
        saveClipboardPreferences()
        if isPaused {
            clipboardWatchTask?.cancel()
            clipboardWatchTask = nil
            let baseline = clipboardWatcher.changeCount
            Task { [clipboardWatcher] in await clipboardWatcher.passOver(upTo: baseline) }
            startClipboardPauseTimerIfNeeded()
        } else {
            followTheClipboardSwitch()
        }
    }

    private func startClipboardPauseTimerIfNeeded() {
        guard clipboardPauseTask == nil, let until = clipboardPauseUntil else { return }
        let delay = max(0, until.timeIntervalSinceNow)
        clipboardPauseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.clipboardPauseUntil = nil
            self?.clipboardPreferences.pausedUntil = nil
            self?.saveClipboardPreferences()
            self?.clipboardPauseTask = nil
            self?.followTheClipboardSwitch()
        }
    }

    /// Adds or removes bundle identifiers through private preferences and a running-app picker.
    private func manageClipboardExclusions() {
        guard !clipboardPreferencesUnreadable else { return }
        let identifiers = clipboardPreferences.excludedBundleIdentifiers.sorted()
        let alert = NSAlert()
        alert.messageText = "Clipboard exclusions"
        alert.informativeText =
            identifiers.isEmpty
            ? "No apps are excluded. The frontmost app at copy detection time is used; macOS does not identify the pasteboard writer."
            : "Excluded: " + identifiers.joined(separator: ", ")
        alert.addButton(withTitle: "Add Running App…")
        alert.addButton(withTitle: "Remove…")
        alert.addButton(withTitle: "Done")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            ApplicationPicker.chooseClipboardApplication { [weak self] identifier in
                guard let self else { return }
                clipboardPreferences.exclude(identifier)
                saveClipboardPreferences()
            }
        case .alertSecondButtonReturn:
            guard !identifiers.isEmpty else { return }
            let removal = NSAlert()
            removal.messageText = "Remove an excluded app"
            let menu = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
            menu.addItems(withTitles: identifiers)
            removal.accessoryView = menu
            removal.addButton(withTitle: "Remove")
            removal.addButton(withTitle: "Cancel")
            if removal.runModal() == .alertFirstButtonReturn {
                clipboardPreferences.include(identifiers[max(0, menu.indexOfSelectedItem)])
                saveClipboardPreferences()
            }
        default: break
        }
    }

    private func saveClipboardPreferences() {
        guard !clipboardPreferencesUnreadable else { return }
        do {
            try clipboardPreferencesFile.save(clipboardPreferences)
            let excludedApplications = clipboardPreferences.excludedBundleIdentifiers
            Task { [clipboardWatcher] in
                await clipboardWatcher.setExcludedApplications(excludedApplications)
                await clipboardWatcher.passOver(upTo: clipboardWatcher.changeCount)
            }
        } catch { report(error) }
    }

    private static func clipboardPreferencesUnreadableNotice(canRestore: Bool) -> MainNotice {
        MainNotice(
            message:
                "Your exclusion list could not be read. Clipboard capture is off until you restore it.",
            symbolName: "exclamationmark.triangle", tone: .critical,
            action: canRestore
                ? MainAction(title: "Restore exclusions", intent: .restoreClipboardPreferences)
                : nil)
    }

    private func restoreClipboardPreferences() {
        guard let clipboardPreferencesSetAside else { return }
        do {
            clipboardPreferences = try clipboardPreferencesFile.restore(from: clipboardPreferencesSetAside)
            self.clipboardPreferencesSetAside = nil
            clipboardPreferencesUnreadable = false
            clipboardPauseUntil = clipboardPreferences.pausedUntil
            actionNotice = nil
            followTheClipboardSwitch()
            refreshMainWindow()
        } catch {
            actionNotice = Self.clipboardPreferencesUnreadableNotice(canRestore: true)
            refreshMainWindow()
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
    func readMenuClips() async {
        let clips: [Clip]
        if settings.clipboardEnabled {
            clips = Array(await clipboard.clips(keeping: retention).prefix(MenuBarPresenter.clipCount))
            await reportUnreadableClipboardIndexes()
        } else {
            clips = []
        }
        guard clips != menuClips else { return }
        menuClips = clips
        refreshMenuBar()
    }

    /// Reports an incompatible format or tells the user where a damaged index was preserved.
    private func reportUnreadableClipboardIndexes() async {
        let unsupportedVersions = await clipboard.takeUnsupportedFormatVersions()
        if !unsupportedVersions.isEmpty {
            let versions = unsupportedVersions.map(String.init).joined(separator: ", ")
            let message =
                "Clipboard history uses unsupported version \(versions) and is read-only. Update Uttrflow before changing clipboard history."
            let notice = MainNotice(message: message, symbolName: "externaldrive", tone: .warning)
            actionNotice = notice
            panel?.notice = PanelNotice(symbolName: notice.symbolName, message: message)
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            announce(message, urgently: false)
            refreshMainWindow()
            return
        }
        let copies = await clipboard.takeUnreadableIndexSetAsides()
        guard !copies.isEmpty else { return }
        let locations = copies.map(\.path).joined(separator: ", ")
        let message = "A damaged clipboard index was preserved at \(locations)."
        let notice = MainNotice(
            message: message, symbolName: "externaldrive", tone: .warning)
        actionNotice = notice
        panel?.notice = PanelNotice(symbolName: notice.symbolName, message: message)
        if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
        announce(message, urgently: false)
        refreshMainWindow()
    }

    /// Tells the user once when a clipboard writer takes longer than the read limit.
    private func reportClipboardCaptureDegraded() {
        let message = "A clipboard copy took too long to read. Capture will retry automatically."
        let notice = MainNotice(message: message, symbolName: "doc.on.clipboard", tone: .warning)
        actionNotice = notice
        panel?.notice = PanelNotice(symbolName: notice.symbolName, message: message)
        if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
        announce(message, urgently: false)
        refreshMainWindow()
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

        var refused: [ShortcutAction: HotkeyError] = [:]
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
                refused[action] = error
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
            await copyLastTranscript()
        // Watched through the tap rather than registered, so they never arrive here.
        case .dictate, .editCommand:
            break
        }
    }

    /// Puts the last dictation back at the caret by the route a dictation takes, never the clipboard.
    private func pasteLastTranscript() async {
        guard let text = await keptLastTranscript() else {
            sayNoLastTranscript(to: "paste")
            return
        }
        do {
            _ = try await lastTranscriptInserter.insert(text)
        } catch {
            render(.failed(DictationFailure(error)))
        }
    }

    /// Shown and spoken, so a shortcut with nothing to act on never looks broken.
    private func sayNoLastTranscript(to verb: String) {
        Self.log.notice("\(verb, privacy: .public) last transcript: nothing dictated yet")
        let message = "There is no transcript to \(verb) yet."
        actionNotice = MainNotice(message: message, symbolName: "info.circle", tone: .neutral)
        announce(message, urgently: false)
    }

    /// Writes the clipboard on purpose, which is the one shortcut whose whole job that is.
    private func copyLastTranscript() async {
        guard let text = await keptLastTranscript() else {
            sayNoLastTranscript(to: "copy")
            return
        }
        let result: PasteboardWriteResult
        if DictationTextPresentation(text).isSecret {
            result = announcingPasteboard.writeConcealedText(text)
        } else {
            result = announcingPasteboard.writeTransientText(text, richText: nil)
        }
        guard result.didWrite else {
            showClipboardCopyFailure()
            return
        }
        sayCopiedForMainWindow()
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
        if settings.clipboardEnabled && !isClipboardPaused {
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
            insert(text, richText: richText, targeting: destination, used: used, forPanel: true)
        case .closeAndInsert(let text, let used):
            // Closed first: insertion declines outright while Uttrflow is frontmost.
            let destination = panelTarget ?? InsertionDestination(applicationName: nil, bundleIdentifier: nil)
            closeQuickPanel()
            insert(text, targeting: destination, used: used, forPanel: true)
        case .closeAndInsertConcealed(let text, let used):
            let destination = panelTarget ?? InsertionDestination(applicationName: nil, bundleIdentifier: nil)
            closeQuickPanel()
            insert(text, concealed: true, targeting: destination, used: used, forPanel: true)
        case .copyAndSay(let text, let notice, let used):
            // Stays open: the panel is the only surface left to say this on.
            let copied = putOnClipboard(text, used: used)
            panel?.notice = copied ? notice : Self.clipboardCopyFailedNotice
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            if copied { closeAfterReading() }
        case .copyConcealedAndSay(let text, let notice, let used):
            let copied = putOnClipboard(text, concealed: true, used: used)
            panel?.notice = copied ? notice : Self.clipboardCopyFailedNotice
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            if copied { closeAfterReading() }
        case .copyImageAndSay(let clip, let notice):
            let owner = PanelLateRequest(opens: quickPanel.opens, sheet: panel?.sheet)
            Task { [weak self] in
                guard let self else { return }
                let outcome = await putImageOnClipboard(clip)
                guard owner.isSameOpen(panel, opens: quickPanel.opens) else { return }
                // A picture that went between the draw and the keypress is said, never claimed as copied.
                switch outcome {
                case .copied:
                    panel?.notice = notice
                    closeAfterReading()
                case .missingPicture:
                    panel?.notice = Self.pictureMissingNotice(clip)
                    closeAfterReading()
                case .writeRefused:
                    panel?.notice = Self.clipboardCopyFailedNotice
                }
                if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            }
        case .closeAndCopy(let text, let richText, let used):
            // Onto the clipboard and no further: the user will paste it somewhere else.
            if putOnClipboard(text, richText: richText, used: used) {
                closeQuickPanel()
            } else {
                panel?.notice = Self.clipboardCopyFailedNotice
                if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            }
        case .closeAndCopyConcealed(let text, let used):
            if putOnClipboard(text, concealed: true, used: used) {
                closeQuickPanel()
            } else {
                panel?.notice = Self.clipboardCopyFailedNotice
                if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
            }
        case .closeAndCopyImage(let clip):
            let owner = PanelLateRequest(opens: quickPanel.opens, sheet: panel?.sheet)
            Task { [weak self] in
                guard let self else { return }
                let outcome = await putImageOnClipboard(clip)
                guard owner.isSameOpen(panel, opens: quickPanel.opens), outcome == .copied else {
                    if owner.isSameOpen(panel, opens: quickPanel.opens) {
                        panel?.notice =
                            outcome == .missingPicture
                            ? Self.pictureMissingNotice(clip) : Self.clipboardCopyFailedNotice
                        if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
                        if outcome == .missingPicture { closeAfterReading() }
                    }
                    return
                }
                closeQuickPanel()
            }
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

    /// Carries out a panel change and redraws from the state returned by the store.
    func apply(_ change: PanelChange) {
        let owner = PanelLateRequest(opens: quickPanel.opens, sheet: panel?.sheet)
        Task {
            do {
                try await carryOut(change, owner: owner)
            } catch let failure as ClipboardStoreError {
                // F10 — stays open holding the failure, which must look different from a success.
                Self.log.error(
                    "clipboard write refused: \(failure.userMessage, privacy: .public)")
                guard owner.isSameOpen(panel, opens: quickPanel.opens) else { return }
                panel?.notice = .writeFailed(failure.userMessage)
            }
            await refreshPanelIfOpen()
            await readMenuClips()
        }
    }

    /// The write itself, with every refusal allowed to reach the caller.
    private func carryOut(
        _ change: PanelChange, owner: PanelLateRequest
    ) async throws(ClipboardStoreError) {
        switch change {
        case .setAlias(let id, let alias):
            _ = try await clipboard.setAlias(alias, of: id, keeping: retention)
        case .setCategory(let id, let category):
            _ = try await clipboard.setCategory(category, of: id, keeping: retention)
        case .setPinned(let id, let isPinned):
            _ = try await clipboard.setPinned(isPinned, of: id, keeping: retention)
        case .setSecret(let id, let isSecret):
            _ = try await clipboard.setSecret(isSecret, of: id, keeping: retention)
        case .delete(let id):
            // F7, F9 — kept in hand, because the store forgets it the moment this returns.
            let held = panel?.clips.first { $0.id == id }.map { [$0] } ?? []
            let ticket = undoOffer.offer(held)
            // The earlier delete's timer must not expire this one's offer before its own starts.
            undoTask?.cancel()
            panel?.canUndoDelete = !held.isEmpty
            panel?.undoAnnouncementID = UUID()
            Self.log.info(
                "delete: undoable=\(!held.isEmpty, privacy: .public) flag=\(self.panel?.canUndoDelete == true, privacy: .public)"
            )
            let deletion = Task { [clipboard, retention] () -> Result<Void, ClipboardStoreError> in
                await clipboard.forgetHeldPictures()
                do throws(ClipboardStoreError) {
                    _ = try await clipboard.delete(
                        id, keeping: retention, holdingPicture: !held.isEmpty)
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }
            undoOffer.trackDelete(deletion, ticket: ticket)
            // Only the latest delete can be undone, so an earlier one's picture is let go first.
            switch await deletion.value {
            case .success:
                break
            case .failure(let error):
                throw error
            }
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
            let ticket = undoOffer.offer([])
            undoTask?.cancel()
            panel?.canUndoDelete = false
            let deletion = Task { [clipboard, retention] () -> Result<[Clip], ClipboardStoreError> in
                await clipboard.forgetHeldPictures()
                do throws(ClipboardStoreError) {
                    let deleted = try await clipboard.deleteCategoryForUndo(
                        name, keeping: retention)
                    return .success(deleted)
                } catch {
                    return .failure(error)
                }
            }
            let deleteGate = Task { () -> Result<Void, ClipboardStoreError> in
                switch await deletion.value {
                case .success: return .success(())
                case .failure(let error): return .failure(error)
                }
            }
            undoOffer.trackDelete(deleteGate, ticket: ticket)
            switch await deletion.value {
            case .success(let held):
                guard undoOffer.complete(ticket, with: held) else { return }
                panel?.canUndoDelete = !held.isEmpty
                panel?.undoAnnouncementID = UUID()
                await startForgettingTheUndo()
            case .failure(let error):
                if undoOffer.isLatest(ticket) {
                    undoOffer.withdraw()
                    await clipboard.forgetHeldPictures()
                }
                throw error
            }
        case .restore(let clip):
            let deletion = undoOffer.pendingDelete
            undoOffer.withdraw()
            if let deletion {
                switch await deletion.value {
                case .success:
                    break
                case .failure(let error):
                    throw error
                }
            }
            let notice = try await PanelUndoRestorer.restore(
                [clip], to: clipboard, keeping: retention)
            if owner.isSameOpen(panel, opens: quickPanel.opens) {
                panel?.notice = notice
                panel?.canUndoDelete = false
            }
        }
    }

    /// Expires the undo offer, so an old delete cannot be reversed by a keystroke meant for something else.
    private func startForgettingTheUndo() async {
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: AppDelegate.undoWindow)
            guard let self, !Task.isCancelled else { return }
            await PanelUndoExpiry.expire(
                withdraw: {
                    self.undoOffer.withdraw()
                    self.panel?.canUndoDelete = false
                },
                releasingPictures: { await self.clipboard.forgetHeldPictures() })
            await self.refreshPanelIfOpen()
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
        case .pin, .unpin, .markNotSecret, .markSecret:
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
            guard let claim = undoOffer.claimForRestore() else { return }
            let owner = PanelLateRequest(opens: quickPanel.opens, sheet: panel?.sheet)
            undoTask?.cancel()
            panel?.canUndoDelete = false
            intentWork = Task { [weak self] in
                guard let self else { return }
                do throws(ClipboardStoreError) {
                    try await claim.waitForDelete()
                    let notice = try await PanelUndoRestorer.restore(
                        claim.clips, to: self.clipboard, keeping: self.retention)
                    if owner.isSameOpen(self.panel, opens: self.quickPanel.opens) {
                        self.panel?.notice = notice
                    }
                } catch {
                    if owner.isSameOpen(self.panel, opens: self.quickPanel.opens) {
                        self.panel?.notice = .writeFailed(error.userMessage)
                    }
                }
                await self.refreshPanelIfOpen()
            }
        case .format(let id):
            runFormatter(on: id)
        case .openSettings:
            // Closed first: Settings activates the app, and the panel would belong to nothing.
            closeQuickPanel()
            show(.settings(.general))
        case .insert, .insertCleaned, .reveal, .alias, .move, .delete, .renameCategory, .deleteCategory,
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
                endFormatting(request, with: .unreadable)
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
                endFormatting(request, with: .unfaithful)
                return
            }
            guard let prepared else {
                endFormatting(request, with: .alreadyFormatted)
                return
            }
            // A panel closed, reopened, re-sheeted, edited or formatted again since is left alone.
            guard request.accepts(into: panel, opens: quickPanel.opens, latestRun: formatterRuns)
            else { return }
            panel?.remember(prepared)
            panel?.sheet = .formatting(id, formatted: produced)
            if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
        }
    }

    /// Says how a Format run ended without a sheet, unless the panel has moved on since the question.
    private func endFormatting(_ request: PanelFormatRequest, with ending: PanelFormatEnding) {
        guard request.accepts(into: panel, opens: quickPanel.opens, latestRun: formatterRuns) else { return }
        panel?.notice = ending.notice
        if let snapshot = panel { quickPanel.update(PanelPresenter.present(snapshot)) }
    }

    /// Notes a clip was reached for, from the three methods that place one so no path can forget.
    private func markUsed(_ id: Clip.ID?) {
        guard let id else { return }
        let window = retention
        Task { [clipboard] in
            await clipboard.markUsed(id, at: Date(), keeping: window)
        }
    }

    private enum ImageCopyOutcome: Equatable { case copied, missingPicture, writeRefused }

    /// Puts a picture's PNG on the clipboard through the one pasteboard.
    private func putImageOnClipboard(_ clip: Clip) async -> ImageCopyOutcome {
        guard let image = clip.image, let data = await clipboard.imageData(for: image) else {
            Self.log.error("picture missing at copy: \(clip.id, privacy: .public)")
            return .missingPicture
        }
        guard announcingPasteboard.setImage(data).didWrite else { return .writeRefused }
        markUsed(clip.id)
        return .copied
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

    /// Adds a chosen dictation to clipboard history while the Clipboard switch is on.
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
        targeting destination: InsertionDestination? = nil, used: Clip.ID?, forPanel: Bool = false
    ) {
        markUsed(used)
        let clipInserter: any TextInserting =
            switch (forPanel, concealed) {
            case (true, true): panelSecretInserter
            case (true, false): panelClipInserter
            case (false, true): secretInserter
            case (false, false): self.clipInserter
            }
        Task { [weak self, clipInserter] in
            do {
                let attempt: InsertionAttempt
                if let destination {
                    attempt = try await clipInserter.insert(text, richText: richText, targeting: destination)
                } else {
                    attempt = try await clipInserter.insert(text, richText: richText)
                }
                let arrival = forPanel ? "" : " arrival=\(attempt.arrival.rawValue)"
                Self.log.info(
                    "clip inserted by \(attempt.method.rawValue, privacy: .public)\(arrival, privacy: .public)"
                )
                if forPanel { self?.reportPanelPaste(.text(attempt)) }
            } catch {
                // Every strategy refused, including the one that cannot.
                let why = (error as? any UttrflowFailure)?.userMessage ?? SuggestionLog.failure(error)
                Self.log.error("clip insertion failed: \(why, privacy: .public)")
                self?.reportPanelPaste(forPanel ? .textCouldNotPaste : .textRefused)
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
        await reportUnreadableClipboardIndexes()
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
    @discardableResult
    private func putOnClipboard(
        _ text: String, richText: String? = nil, concealed: Bool = false, used: Clip.ID?
    ) -> Bool {
        // A secret goes up marked, so no other clipboard history records it in plain text.
        let result: PasteboardWriteResult
        guard !concealed else {
            result = announcingPasteboard.setConcealedText(text)
            if result.didWrite { markUsed(used) }
            return result.didWrite
        }
        // E2, E3 — both flavours, so the receiving application takes the one it understands.
        result = announcingPasteboard.setText(text, richText: richText)
        if result.didWrite { markUsed(used) }
        return result.didWrite
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

    private static var clipboardCopyFailedNotice: PanelNotice {
        PanelNotice.writeFailed(MainNotice.clipboardCopyFailed.message)
    }

    private func showClipboardCopyFailure() {
        actionNotice = .clipboardCopyFailed
        announce(MainNotice.clipboardCopyFailed.message, urgently: false)
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
        // A press that started or failed a dictation is an event that already arrived, so no timer is needed.
        switch state {
        case .recording, .failed: checkSecureInput()
        default: break
        }
        telemetry?.observe(state, language: settings.profile.preferredLanguages.first)
        if case .inserted(let outcome) = state { noteCleanUp(outcome) }
        // Recorded before the menu is drawn, and kept even when insertion failed. §19.
        switch state {
        case .inserted(let outcome):
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
            guard let record = DictationRecordMapping.record(for: state, when: Date(), id: UUID())
            else { break }
            keep(record)
            noteStyle(outcome)
        case .failed(let notice):
            Self.log.error(
                """
                dictation failed: \(notice.message, privacy: .public) \
                salvaged=\(notice.transcript != nil, privacy: .public) \
                kept=\(notice.recovery == .retryFromRecording, privacy: .public)
                """)
            if let record = DictationRecordMapping.record(for: state, when: Date(), id: UUID()) {
                // Not an empty set: unmeasured is a different fact from nothing changed.
                keep(record)
            }
        case .idle, .recording, .transcribing, .tidying, .inserting, .discarded:
            break
        }
        // Whichever way it ended, the row that said "Retrying…" is not retrying any more.
        if state.hasEnded { retryBadge.clear() }
        // After each dictation, since a menu-bar-only user may never open the window that lists them.
        if state.hasEnded { sweepExpired() }

        relay(state)
    }

    /// Says when clean-up fell back, and probes the engines when the preferred one did not run.
    private func noteCleanUp(_ outcome: UttrflowPipeline.DictationOutcome) {
        lastCleanedBy = outcome.cleanedBy
        if let notice = MainNotice.cleanUpSkipped(by: outcome.cleanedBy) {
            actionNotice = notice
            announce(notice.message, urgently: false)
        }
        if !appleIntelligenceFallbackNoticeShown,
            outcome.cleanedBy == .rules,
            let unavailable = outcome.unavailableEngines.first(where: {
                $0.engine == TransformerKind.foundationModels.rawValue
            })
        {
            appleIntelligenceFallbackNoticeShown = true
            let notice = MainNotice.appleIntelligenceUnavailable(unavailable.reason)
            actionNotice = notice
            announce(notice.message, urgently: false)
        }
        if settings.engines.resolvedTransformerPreference.first != outcome.cleanedBy {
            probeTransformers()
        }
    }

    /// Updates every surface that shows the dictation state, then schedules dismissal.
    private func relay(_ state: DictationState) {
        // Kept here, where every change already arrives, so the updater need not ask the pipeline.
        lastDictationState = state
        updates.refresh()
        // The last page of onboarding fills its field with the first dictation.
        onboarding?.dictationChanged(to: state)
        // A dictation's own outcome is newer than any panel paste's report.
        if state != .idle { pasteReport = nil }
        // Dictation takes the microphone, so a try under way gives it up.
        if state.isBusy, wordTrialWork != nil { endWordTrial() }
        if state.isBusy, speechPressure.isReleased { speechPressure.reloaded(at: .now) }
        DictationInProgress.shared.set(dictating: state.isBusy)
        completions?.dictationChanged(isDictating: state.isBusy)

        // Cleared as soon as the recording ends, so a countdown cannot outlive it.
        if !state.isListening {
            recordingAdvice = .keepGoing
            recordingStopGesture = .letGo
        }
        menuBar.update(with: MenuBarPresenter.present(menuBarState(for: state)))
        trackWait(for: state)
        dock.update(with: dockPresentation(for: state))
        announcer.repeatWindow = .milliseconds(settings.handsFreeDoubleTapMilliseconds)
        announce(announcer.announcement(for: state, at: ContinuousClock.now))
        // No page shows a dictation under way, so the pages are read and built only once it has ended.
        if !state.isBusy { refreshMainWindow() }

        scheduleDismissal(after: state)
    }

    /// Starts the clock on the wait at key release and redraws its line each second until the dictation ends.
    private func trackWait(for state: DictationState) {
        guard state.isBusy, !state.isListening else {
            waitStarted = nil
            waitTicker?.cancel()
            waitTicker = nil
            waitAnnounced = false
            return
        }
        guard waitStarted == nil else { return }
        waitStarted = .now
        waitTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, let started = waitStarted else { return }
                let waited = started.duration(to: .now)
                dock.update(with: dockPresentation(for: lastDictationState))
                if let said = WaitLine.announcement(
                    for: lastDictationState, waited: waited, alreadyAnnounced: waitAnnounced)
                {
                    waitAnnounced = true
                    announce(said)
                }
            }
        }
    }

    /// Offers every word one dictation taught in the popover and names the first through VoiceOver.
    func noteLearned(_ entries: [DictionaryEntry]) {
        let learnt = recentlyLearned.record(entries, at: Date())
        guard let line = RecentlyLearned.announcement(for: learnt) else { return }
        announce(line, urgently: false)
        refreshMenuBar()
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

    /// Counts how the user writes in the destination the words went into; never the words themselves.
    private func noteStyle(_ outcome: UttrflowPipeline.DictationOutcome) {
        guard let evidence, !outcome.intoSecureField, !outcome.isFromRecording else { return }
        let app = AppContext(
            applicationName: outcome.insertedInto, bundleIdentifier: outcome.insertedIntoIdentifier)
        let destination = DestinationClassifier.classify(app, overrides: settings.destinations)
        let now = Date()
        let rows = StyleSignals.rows(for: outcome.text, into: destination, day: EvidenceRow.day(of: now))
        noteEvidence(rows, in: evidence, now: now)
    }

    /// Appends pairing rows before the refresh that follows reads them, so the Corrections page shows the veto at once.
    private func notePairing(_ rows: [EvidenceRow]) async {
        guard let evidence, !rows.isEmpty else { return }
        do {
            try await evidence.append(
                rows, keeping: RetentionWindow(days: settings.transcriptRetentionDays, now: Date()))
        } catch {
            Self.log.error("evidence not saved: \(ErrorLog.failure(error), privacy: .public)")
        }
    }

    /// The pairings the ledger holds inside History's window; none without a ledger.
    private func readPairs() async -> [String: ConfusionPairs.Feature] {
        guard let evidence else { return [:] }
        let window = RetentionWindow(days: settings.transcriptRetentionDays, now: Date())
        return ConfusionPairs.project(await evidence.rows(keeping: window))
    }

    /// Appends rows to the ledger inside History's window, off the main actor; a refusal is logged, never shown.
    private func noteEvidence(_ rows: [EvidenceRow], in evidence: EvidenceLedgerStore, now: Date = Date()) {
        guard !rows.isEmpty else { return }
        let window = RetentionWindow(days: settings.transcriptRetentionDays, now: now)
        Task {
            do {
                try await evidence.append(rows, keeping: window)
            } catch {
                Self.log.error("evidence not saved: \(ErrorLog.failure(error), privacy: .public)")
            }
        }
    }

    /// Keeps one dictation, inserted or salvaged, and makes it what the last-transcript shortcuts act on.
    private func keep(_ record: DictationRecord) {
        lastTranscript = record.text
        lastTranscriptID = record.id
        recents.add(record)
        let days = settings.transcriptRetentionDays
        let previous = historyWrite
        historyWrite = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                _ = try await history.append(record, keeping: Retention(days: days, now: Date()))
            } catch {
                // Logged, not rendered: the dictation on screen by now may be a later one.
                Self.log.error("history note not saved: \(DictationFailure(error).message, privacy: .public)")
            }
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
        showRefusedShortcuts()
        refreshMenuBar()
    }

    /// Why the shortcut cannot be heard, for both surfaces that say so. Internal so a test can read it.
    var shortcutUnheard: String? {
        ShortcutArming.unheard(
            secureInputBlocking: secureInput.isBlocking, failure: shortcutArming.failure)
    }

    /// Translates the pipeline's state into the menu's vocabulary, deciding nothing.
    private func menuBarState(for state: DictationState) -> MenuBarState {
        let menu = Self.menuBarDictation(for: state, floatingButtonShown: showsTheFloatingButton)
        return MenuBarState(
            activity: menu.activity,
            failure: menu.failure,
            speechModel: speechReadiness,
            speechLoadElapsed: speechLoadStarted.map { $0.duration(to: .now) } ?? .zero,
            recordingAdvice: recordingAdvice,
            stopGesture: recordingStopGesture,
            recents: recents.previews.map {
                MenuBarRecent(
                    id: $0.id,
                    title: $0.title,
                    fullText: $0.isSecret ? $0.title : $0.dictation.text,
                    isSecret: $0.isSecret)
            },
            clips: menuClips,
            learned: recentlyLearned.current(at: Date()),
            updateProgress: updates.progress,
            canCheckForUpdates: UpdateController.isConfigured,
            features: menuBarFeatures(for: settings),
            shortcuts: settings.shortcuts,
            unarmedShortcuts: Set(unarmedShortcuts.keys),
            shortcutUnheard: shortcutUnheard,
            suggestionUnheard: suggestionSecureInputNotice,
            suggestionRuntime: suggestionRuntime,
            suggestionModel: suggestionModel,
            activation: settings.hotkeyActivation,
            speechModelBytes: SpeechModel.default.downloadBytes
        )
    }

    /// Uses the same stored, paused and per-application gate the suggestion coordinator uses.
    private func menuBarFeatures(for settings: Settings, at moment: Date = Date()) -> MenuBarFeatures {
        MenuBarFeatures(
            settings, applicationBundleIdentifier: suggestionApplicationBundleIdentifier, at: moment)
    }

    private func updateSuggestionApplicationContext() {
        suggestionApplicationBundleIdentifier = Self.suggestionApplicationContext(
            previous: suggestionApplicationBundleIdentifier,
            frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    nonisolated static func suggestionApplicationContext(
        previous: String?, frontmost: String?
    ) -> String? {
        guard let frontmost,
            !frontmost.hasPrefix(SuggestionCoordinator.uttrflowBundlePrefix)
        else { return previous }
        return frontmost
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
        case .insertRecent(let id):
            guard let recent = recents.entries.first(where: { $0.id == id }) else { return }
            // The app's own inserter: a fresh one would get the unannouncing pasteboard.
            insert(
                recent.text, concealed: DictationTextPresentation(recent.text).isSecret, used: nil)
        case .copyRecent(let id):
            guard let recent = recents.entries.first(where: { $0.id == id }) else { return }
            // And through the helper that announces the write, for the same reason.
            if !putOnClipboard(
                recent.text, concealed: DictationTextPresentation(recent.text).isSecret, used: nil)
            {
                showClipboardCopyFailure()
            }
        case .insertClip(let id):
            guard let clip = menuClips.first(where: { $0.id == id }) else { return }
            if clip.image != nil {
                insertImage(clip)
            } else {
                insert(clip.text, concealed: clip.kind == .secret, used: clip.id)
            }
        case .copyClip(let id):
            guard let clip = menuClips.first(where: { $0.id == id }) else { return }
            if clip.image != nil {
                Task { [weak self] in
                    guard let self else { return }
                    if await putImageOnClipboard(clip) != .copied { showClipboardCopyFailure() }
                }
            } else {
                if !putOnClipboard(
                    clip.text, richText: clip.richText, concealed: clip.kind == .secret, used: clip.id)
                {
                    showClipboardCopyFailure()
                }
            }
        case .undoLearnedWord(let id):
            recentlyLearned.forget(id)
            refreshMenuBar()
            // The Dictionary page's delete, so an undone word is refused rather than relearned.
            act { try await self.dictionary.remove(id) }
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
    private func show(_ destination: UttrflowUX.AppLocation) {
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
    private(set) var lastOpened: UttrflowUX.AppLocation?
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
            measureSnippetArrival()
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
            isOnboarding: onboarding != nil,
            isSuggesting: completions?.isActiveForUpdate == true)
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
        if reset.targets.contains(.clipboard) {
            let deletion = undoOffer.pendingDelete
            undoOffer.withdraw()
            undoTask?.cancel()
            undoTask = nil
            panel?.canUndoDelete = false
            Task { [clipboard] in
                if let deletion { _ = await deletion.value }
                await clipboard.forgetHeldPictures()
            }
        }
        guard reset.forgetsTheLastDictation else {
            refreshMainWindow()
            return
        }
        lastCleaning = nil
        lastTidyTally = TidyTally()
        lastCleanedBy = nil
        forgetLastTranscript()
        Task { [weak self] in
            await self?.diagnostics.forget()
            self?.refreshMainWindow()
        }
    }

    /// Drops the words the paste and copy shortcuts put back, with the record they came from.
    private func forgetLastTranscript() {
        lastTranscriptGeneration += 1
        lastTranscript = nil
        lastTranscriptID = nil
    }

    /// The last transcript only while History still keeps its record, so retention forgets it too.
    private func keptLastTranscript() async -> String? {
        guard let text = lastTranscript, !text.isEmpty, let id = lastTranscriptID else { return nil }
        let generation = lastTranscriptGeneration
        await historyWrite?.value
        let retention = Retention(days: settings.transcriptRetentionDays, now: Date())
        let kept = await history.records(keeping: retention).contains { $0.id == id }
        guard generation == lastTranscriptGeneration, id == lastTranscriptID else { return nil }
        guard kept else {
            forgetLastTranscript()
            return nil
        }
        return text
    }

    /// Restores the newest retained dictation so paste-last works after relaunch.
    func restoreLastTranscript() async {
        let generation = lastTranscriptGeneration
        let retention = Retention(days: settings.transcriptRetentionDays, now: Date())
        let newest = await history.records(keeping: retention).first
        guard generation == lastTranscriptGeneration, lastTranscript == nil, let newest else {
            return
        }
        lastTranscript = newest.text
        lastTranscriptID = newest.id
    }

    /// Redraws from a fresh snapshot, reading everything on one hop so the pages agree.
    private func refreshMainWindow() {
        refreshGeneration += 1
        let reading = refreshGeneration
        Task { [weak self] in
            guard let self else { return }
            let measurements = await diagnostics.recorded
            let decoding = await diagnostics.decoding
            lastWaits = await diagnostics.waits.timed
            lastMeasurements = measurements
            lastDecoding = decoding
            lastSpeechModelLoads = speechModelLoadLog.history().records
            lastCleaning = await diagnostics.lastCleaning
            lastTidyTally = await diagnostics.tidyTally
            lastVocabularyPrompt = await diagnostics.vocabularyPrompt
            let kept = await history.records(
                keeping: Retention(days: settings.transcriptRetentionDays, now: Date()))
            self.kept = kept
            hasReadHistory = true
            knownRecordings = await recordings.waiting(now: Date())
            recents = RecentDictations(showing: kept)
            knownWords = await dictionary.allEntries()
            knownRefusals = await dictionary.refusedWords()
            knownPairs = await readPairs()
            ledgerRefusal = await evidence?.refusal()
            knownSnippets = await snippets.snippets()
            let suggestionCounts: SuggestionCounts?
            if settings.suggestions.isEnabled, let completions {
                do {
                    let counts = try await completions.insightCounts()
                    suggestionCounts = SuggestionCounts(
                        entries: counts.entries, uses: counts.uses, accepted: counts.accepted,
                        rejected: counts.rejected, selfSourced: counts.selfSourced)
                } catch {
                    Self.log.error("the suggestion corpus counts could not be read")
                    suggestionCounts = nil
                }
            } else {
                suggestionCounts = nil
            }
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
            mainWindow?.update(
                mainContent(measurements: measurements, suggestionCounts: suggestionCounts))
        }
    }

    private func mainContent(
        measurements: [StageMeasurement], suggestionCounts: SuggestionCounts? = nil
    ) -> MainContent {
        let suggestionCounts =
            settings.suggestions.isEnabled
            ? suggestionCounts ?? mainWindow?.content.insights.suggestionCounts : nil
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
                    keepsRecordings: true, canKeepAsClip: surfaces.watchesTheClipboard,
                    recordings: knownRecordings,
                    retrying: retryingRecording, playing: playback.playing, now: now,
                    hasReadHistory: hasReadHistory)),
            dictionary: dictionaryPage(at: now, corrections: corrections),
            corrections: CorrectionsPresenter.page(
                for: CorrectionsSnapshot(
                    corrections: corrections, dictations: entries,
                    query: query(for: .corrections),
                    scope: CorrectionsScope(rawValue: scope(for: .corrections)) ?? .all,
                    settings: settings,
                    now: now, pairs: knownPairs)),
            insights: InsightsPresenter.page(
                for: InsightsSnapshot(
                    entries: entries, settings: settings,
                    range: InsightsRange(rawValue: scope(for: .insights)), now: now,
                    hasReadHistory: hasReadHistory, suggestionCounts: suggestionCounts)),
            snippets: snippetsPage(at: now),
            diagnostics: DiagnosticsPresenter.page(
                for: DiagnosticsSnapshot(
                    engines: settings.engines, speechInUse: speechInUse,
                    transformerAvailability: transformerAvailability,
                    speechModel: speechModelPresence, speechReadiness: speechReadiness,
                    speechLoadFailure: speechLoadFailure,
                    permissions: knownPermissions,
                    dictationShortcutArmed: surfaces.listensForDictation
                        && shortcutArming.failure == nil,
                    hasDefaultInputDevice: SettingsCapabilities.hasAudioInput,
                    measurements: measurements, vocabularyPrompt: lastVocabularyPrompt,
                    decoding: lastDecoding, waits: lastWaits,
                    speechModelLoads: lastSpeechModelLoads,
                    cleaning: lastCleaning,
                    tidyTally: lastTidyTally,
                    lastCleanedBy: lastCleanedBy,
                    suggestionModel: suggestionModel, version: .ofThisBuild,
                    machine: MachineDescription.current, arrivals: entries.map(\.arrival),
                    qualityLayers: qualityLayers, learnedState: ledgerRefusal)),
            account: accountPage(at: now),
            shortcutKeycaps: SettingsShortcut.keycaps(for: settings.hotkey))
    }

    /// The Dictionary page as the last reading of the words draws it.
    private func dictionaryPage(at now: Date, corrections: [Correction]) -> DictionaryPresentation {
        DictionaryPresenter.page(
            for: DictionarySnapshot(
                entries: knownWords, draft: wordDraft, refusal: wordRefusal,
                query: query(for: .dictionary), filter: scope(for: .dictionary),
                sort: sorts[.dictionary] ?? "", corrections: corrections, now: now,
                packed: lastVocabularyPrompt.isEmpty ? nil : lastVocabularyPrompt,
                refused: knownRefusals, trial: wordTrial))
    }

    /// The Snippets page as the last reading of the snippets draws it.
    private func snippetsPage(at now: Date) -> SnippetsPresentation {
        SnippetsPresenter.page(
            for: SnippetsSnapshot(
                snippets: knownSnippets, draft: snippetDraft, refusal: snippetRefusal,
                query: query(for: .snippets), sort: sorts[.snippets] ?? "", now: now,
                arrival: snippetArrival, dictionary: knownWords))
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
    /// How the tidy route ended for recent pieces, read on the same hop as the timings.
    private var lastTidyTally = TidyTally()
    /// The word spellings in the last recogniser prompt, held locally for Diagnostics.
    private var lastVocabularyPrompt: [String] = []
    /// What the dictation pipeline last reported. See where it is written.
    private var lastDictationState: DictationState = .idle
    private var announcer = DictationAnnouncer<ContinuousClock.Instant>(
        repeatWindow: DictationController<ContinuousClock>.doubleTapWindow)
    private var snippetEditorIsOpen = false
    /// The same, for the word editor.
    private var wordEditorIsOpen = false
    /// Why the last Save was refused, per editor, until the next keystroke clears it.
    private var wordRefusal: String?
    /// The spoken try of a dictionary word under way or last finished, and the work running it.
    private var wordTrial: DictionaryTrial?
    private var wordTrialWork: Task<Void, Never>?
    private var snippetRefusal: String?
    /// How the snippet draft's trigger arrives when said, measured off the main actor as the user types.
    private var snippetArrival: SnippetArrival?
    private var snippetArrivalWork: Task<Void, Never>?
    /// Why the last delete, flag, restore or undo did not happen, until one of them works or the page changes.
    private(set) var actionNotice: MainNotice?
    /// The complete snippet held for the short main-window undo window.
    private var deletedSnippet: Snippet?
    private var snippetUndoTask: Task<Void, Never>?
    /// The one launch-time rewrite of legacy dictionary spellings.
    var dictionaryMigrationWork: Task<Void, Never>?

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
    /// The spellings the dictionary refuses to learn, newest first, from the latest reading.
    private var knownRefusals: [String] = []
    private var knownSnippets: [Snippet] = []
    private var knownEntitlement: Entitlement?
    /// When the signed-in account was created, from the unsigned profile beside the entitlement.
    private var knownMemberSince: Date?
    /// The person's picture and the path it came from, kept together so it is fetched once per account.
    private var knownPicture: (path: String, bytes: Data)?
    /// The timings last read, so a keystroke redraws without hopping to the actor.
    private var lastMeasurements: [StageMeasurement] = []
    /// The decode effort last read, so a keystroke redraw uses the same bounded session window.
    private var lastDecoding: [DecodeEffort] = []
    /// The last dictations' waits after key-up, as Diagnostics last read them.
    private var lastWaits: [TimedWait] = []
    /// The speech model loads last read from their log.
    private var lastSpeechModelLoads: [SpeechModelLoadRecord] = []
    /// Whether the main window's pages were last skipped because the window is out of sight.
    private var mainWindowIsBehind = false
    /// Everything the store keeps, which is not ``recents`` — that is the menu's five.
    private var kept: [DictationRecord] = []
    /// Whether ``kept`` has been read yet, so Home never shows its first-run page before it knows.
    private var hasReadHistory = false
    /// Recordings whose words were lost, as of the last refresh.
    private var knownRecordings: [KeptRecording] = []
    /// What the ledger says about each heard-to-meant pairing, as of the last refresh.
    private var knownPairs: [String: ConfusionPairs.Feature] = [:]
    /// Why the ledger is set aside, as of the last refresh, so Diagnostics can say so.
    private var ledgerRefusal: EvidenceLedgerError?
    /// The recording the pipeline is running again, so its row can say so.
    private var retryBadge = RetryBadgeOwnership()
    private var retryingRecording: UUID? { retryBadge.recording }
    /// The kept recording History is playing back, one at a time.
    private lazy var playback: RecordingPlayback = {
        let playback = RecordingPlayback()
        playback.onChange = { [weak self] in self?.redrawMainWindow() }
        return playback
    }()

    /// Clears the "Retrying…" badge of a retry the pipeline refused or abandoned.
    private func dropRetryingBadge(_ id: UUID) {
        guard retryBadge.finish(id) else { return }
        redrawMainWindow()
    }

    /// Says why a retry did not start, where the person just pressed Retry.
    private func reportRetryBusy() {
        let notice = MainNotice(
            message: "Finish the current dictation first.",
            symbolName: "arrow.clockwise", tone: .warning)
        actionNotice = notice
        announce(notice.message, urgently: true)
        refreshMainWindow()
    }

    /// The last answer each gate gave; absent means unchecked, which the pages draw as silence.
    private var knownPermissions: [PermissionKind: PermissionStatus] = [:]
    /// Trust read while idle, so turning Accessibility off shows in Diagnostics without a dictation failing first.
    private lazy var accessibilityTrust = PermissionWatcher(gate: AccessibilityPermissionGate()) {
        [weak self] _ in self?.refreshMainWindow()
    }

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
            if putOnClipboard(text, concealed: DictationTextPresentation(text).isSecret, used: nil) {
                sayCopiedForMainWindow()
            } else {
                showClipboardCopyFailure()
            }
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
            guard retryBadge.begin(id) else {
                reportRetryBusy()
                return
            }
            if playback.playing == id { playback.stop() }
            redrawMainWindow()
            retryWork = Task { [weak self] in
                guard let self, await self.pipeline?.retry(id) != true else { return }
                self.dropRetryingBadge(id)
                self.reportRetryBusy()
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

        case .keepDictationAsClip(let id):
            guard surfaces.watchesTheClipboard else { return }
            Task { [weak self] in
                guard let self else { return }
                let retention = Retention(days: self.settings.transcriptRetentionDays, now: Date())
                guard
                    let entry = await self.history.records(keeping: retention).first(where: { $0.id == id }),
                    let write = self.recordAsClip(entry.text, of: id)
                else { return }
                await write.value
            }

        case .sort(let order):
            guard let page = mainWindow?.page else { return }
            sorts[page] = order
            redrawPages([page])
        case .addWord:
            editWord(DictionaryDraft())
        case .fixWord(let written):
            // The wrong spelling is the recogniser's reading of the sound, so it fills "Say it like"; the editor focuses "Write it as".
            actionNotice = nil
            mainWindow?.show(.dictionary)
            editWord(DictionaryDraft(pronunciation: written))
        case .editWord(let id):
            guard let entry = knownWords.first(where: { $0.id == id }) else { return }
            editWord(
                DictionaryDraft(editing: id, word: entry.word, pronunciation: entry.pronunciationField))
        case .cancelWordEdit:
            editWord(nil)
        case .saveWord(let word, let pronunciation):
            saveWord(word, pronunciation: pronunciation)
        case .forgetWords(let ids):
            act { try await self.dictionary.remove(ids) }
        case .restoreWords(let ids):
            act { try await self.dictionary.restore(ids) }
        case .replaceWord(let id, let word, let pronunciation):
            replaceWord(id, with: word, pronunciation: pronunciation)
        case .mergeWords(let kept, let absorbed):
            act { try await self.dictionary.merge(keeping: kept, absorbing: absorbed) }
        case .tryDraft(let word, let pronunciation):
            tryWord(
                DictionaryEntry(
                    word: word, pronunciation: pronunciation.isEmpty ? nil : pronunciation, origin: .added,
                    firstSeen: Date()),
                as: .draft)
        case .tryWord(let id):
            guard let entry = knownWords.first(where: { $0.id == id }) else { return }
            tryWord(entry, as: .word(id))
        case .useSayItLike(let id, let heard):
            if let id, let entry = knownWords.first(where: { $0.id == id }) {
                editWord(
                    DictionaryPresenter.offering(
                        heard,
                        to: DictionaryDraft(
                            editing: id, word: entry.word, pronunciation: entry.pronunciationField)))
            } else if id == nil, let draft = wordDraft {
                endWordTrial()
                mainWindow?.editWord(DictionaryPresenter.offering(heard, to: draft))
                refreshMainWindow()
            }
        case .allowWord(let word):
            act { try await self.dictionary.allowAgain(word) }

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
            snippetUndoTask?.cancel()
            deletedSnippet = nil
            intentWork = Task { [weak self] in
                guard let self else { return }
                do throws(SnippetStoreError) {
                    guard let snippet = await snippets.snippets().first(where: { $0.id == id }) else {
                        _ = try await snippets.delete(id)
                        refreshMainWindow()
                        return
                    }
                    _ = try await snippets.delete(id)
                    deletedSnippet = snippet
                    let notice = MainNotice(
                        message: "Snippet deleted.", symbolName: "trash", tone: .neutral,
                        action: MainAction(title: "Undo", intent: .restoreSnippet(id)))
                    actionNotice = notice
                    announce("Snippet deleted. Undo is available for eight seconds.", urgently: false)
                    snippetUndoTask = Task { [weak self] in
                        try? await Task.sleep(for: AppDelegate.undoWindow)
                        guard let self, !Task.isCancelled else { return }
                        deletedSnippet = nil
                        if actionNotice?.action?.intent == .restoreSnippet(id) { actionNotice = nil }
                        refreshMainWindow()
                    }
                } catch {
                    report(error)
                }
                refreshMainWindow()
            }
        case .restoreClipboardPreferences:
            restoreClipboardPreferences()
        case .restoreSnippet(let id):
            snippetUndoTask?.cancel()
            snippetUndoTask = nil
            guard let snippet = deletedSnippet, snippet.id == id else { return }
            deletedSnippet = nil
            intentWork = Task { [weak self] in
                guard let self else { return }
                do throws(SnippetStoreError) {
                    _ = try await snippets.save(snippet)
                    actionNotice = nil
                } catch {
                    report(error)
                }
                refreshMainWindow()
            }

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
        case .deleteAccount:
            // The server answers first: the local session ends only once the account is gone there.
            intentWork = Task { [weak self, account] in
                do throws(AccountError) {
                    try await account.authentication.deleteAccount()
                } catch {
                    self?.report(error)
                    self?.refreshMainWindow()
                    return
                }
                guard let self else { return }
                account.profiles.clear()
                readAccount()
                actionNotice = nil
                followSession()
            }

        case .undoCorrection(let id):
            let retention = Retention(days: settings.transcriptRetentionDays, now: Date())
            act { [weak self] in
                guard let self else { return }
                // In order: the history decides there was something to undo before the dictionary hears of it.
                guard let reverted = try await history.undoCorrection(id, keeping: retention) else {
                    return
                }
                _ = try await dictionary.recordRevert(of: reverted.entryID)
                await notePairing(EvidenceSources.undone(reverted, day: EvidenceRow.day(of: Date())))
            }

        case .allowPairing(let heard, let meant):
            act { [weak self] in
                await self?.notePairing(
                    ConfusionPairs.allowing(heard: heard, meant: meant, day: EvidenceRow.day(of: Date())))
            }

        case .flagDictation(let id):
            let retention = Retention(days: settings.transcriptRetentionDays, now: Date())
            act { try await self.history.toggleFlag(id, keeping: retention) }

        case .flagDictationAs(let id, let reason):
            let retention = Retention(days: settings.transcriptRetentionDays, now: Date())
            act { try await self.history.flag(id, as: reason, keeping: retention) }

        case .reportDictation(let id):
            let retention = Retention(days: settings.transcriptRetentionDays, now: Date())
            intentWork = Task { [weak self, history, dictionary] in
                guard let record = await history.records(keeping: retention).first(where: { $0.id == id })
                else { return }
                let names = await dictionary.allEntries().map(\.word)
                DictationReportSheet.present(DictationReport(record: record, names: names)) { text in
                    // A concealed copy keeps a report holding a transcript out of clipboard history.
                    self?.putOnClipboard(text, concealed: true, used: nil) ?? false
                }
            }
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
            case .manageClipboardExclusions: manageClipboardExclusions()
            case .exportPersonalData: exportPersonalData()
            case .importPersonalData: importPersonalData()
            case .pauseClipboardCapture(let isOn): setClipboardPaused(isOn)
            case .retrySuggestionModel:
                guard settings.suggestions.isEnabled,
                    suggestionModel == .fetchFailed || suggestionModel == .loadFailed
                else { return }
                prepareTheModelIfNeeded()
            case .openSystemSettings(let pane):
                Task { await openSettingsPane(pane) }
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

    /// Writes both personal lists to a private, user-chosen JSON file.
    @MainActor
    private func exportPersonalData() {
        let disclosure = NSAlert()
        disclosure.alertStyle = .warning
        disclosure.messageText = "The export file is not encrypted"
        disclosure.informativeText = PersonalDataExport.disclosureMessage
        disclosure.addButton(withTitle: "Exclude secret snippets")
        disclosure.addButton(withTitle: "Include all snippets")
        disclosure.addButton(withTitle: "Cancel")
        let choice: PersonalDataExport.Choice
        switch disclosure.runModal() {
        case .alertFirstButtonReturn: choice = .excludeSecretSnippets
        case .alertSecondButtonReturn: choice = .includeAllSnippets
        default: return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Uttrflow-Personal-Data.json"
        panel.canCreateDirectories = true
        panel.message = "This JSON file is not encrypted."
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        intentWork = Task { [weak self, dictionary, snippets, choice] in
            do {
                let archive = PersonalDataExport.archive(
                    dictionary: await dictionary.allEntries(), snippets: await snippets.snippets(),
                    choice: choice)
                try PrivateFile.writeOwnerOnlyAtomically(try archive.encoded(), to: destination)
                self?.showPersonalDataNotice(
                    title: "Personal data exported",
                    message: "Your dictionary and snippets were saved to the file you chose.")
            } catch {
                self?.showPersonalDataNotice(
                    title: "Export could not be completed",
                    message: "Uttrflow could not write the selected file.")
            }
            self?.refreshMainWindow()
        }
    }

    /// Validates the entire local archive before either store is changed, then merges and reports conflicts.
    @MainActor
    private func importPersonalData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "The file is read locally. Existing words and snippet triggers are kept."
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let source = panel.url else { return }

        intentWork = Task { [weak self, dictionary, snippets] in
            do {
                let merged = try await PersonalDataTransfer.importArchive(
                    from: source, into: dictionary, and: snippets)
                let duplicateCount = merged.duplicateWords + merged.duplicateSnippets
                var message =
                    duplicateCount == 0
                    ? "The archive was imported. No duplicate entries were skipped."
                    : "Imported the archive. Skipped \(merged.duplicateWords) duplicate \(merged.duplicateWords == 1 ? "word" : "words") and \(merged.duplicateSnippets) duplicate \(merged.duplicateSnippets == 1 ? "snippet" : "snippets"). Existing entries were kept."
                if merged.skippedInferredWords > 0 {
                    message +=
                        " Kept the \(PersonalDictionaryStore.maximumInferredEntries) strongest learned words and skipped \(merged.skippedInferredWords)."
                }
                if merged.snippetsSayingCommands > 0 {
                    message +=
                        " \(merged.snippetsSayingCommands) imported \(merged.snippetsSayingCommands == 1 ? "snippet has a trigger" : "snippets have triggers") that \(merged.snippetsSayingCommands == 1 ? "says" : "say") a spoken command, so the command runs and the snippet never does."
                }
                self?.showPersonalDataNotice(title: "Import complete", message: message)
            } catch let error as PersonalDataArchiveError {
                let message: String
                switch error {
                case .archiveTooLarge:
                    message = "The archive exceeds the 5 MB import limit. Nothing was imported."
                case .tooManySnippets:
                    message = "The archive exceeds the snippet limit. Nothing was imported."
                case .snippetTooLong:
                    message = "A snippet is longer than the import limit. Nothing was imported."
                case .dictionaryWordTooLong:
                    message = "A dictionary word is longer than the import limit. Nothing was imported."
                case .tooManyDictionaryEntries:
                    message = "The archive exceeds the dictionary word limit. Nothing was imported."
                case .hiddenCharacters:
                    message = "A word or trigger holds a hidden character. Nothing was imported."
                case .unsupportedVersion, .invalidContents:
                    message = "The selected archive is not valid. Nothing was imported."
                }
                self?.showPersonalDataNotice(title: "Import could not be completed", message: message)
            } catch {
                self?.showPersonalDataNotice(
                    title: "Import could not be completed",
                    message: "Uttrflow could not read the selected file or save the imported lists.")
            }
            self?.refreshMainWindow()
        }
    }

    /// States the result in a standard alert, including when no duplicates were found.
    @MainActor
    private func showPersonalDataNotice(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
        endWordTrial()
        editorGeneration += 1
        wordEditorIsOpen = draft != nil
        wordRefusal = nil
        mainWindow?.editWord(draft)
        refreshMainWindow()
    }

    /// Records the word said once on the chosen microphone and probes it; nothing reaches history, recordings or the clipboard.
    private func tryWord(_ entry: DictionaryEntry, as subject: DictionaryTrial.Subject) {
        endWordTrial()
        guard !lastDictationState.isBusy else {
            return showWordTrial(
                DictionaryTrial(subject: subject, phase: .failed("Finish dictating, then try it.")))
        }
        guard let speechEngine else {
            return showWordTrial(
                DictionaryTrial(subject: subject, phase: .failed("The recogniser is not ready yet.")))
        }
        let chosenMicrophone = chosenMicrophone
        // No recording store, so the clip lives only in memory and goes when the try ends.
        let microphone = AVAudioCaptureEngine(
            source: AVAudioEngineMicrophoneSource(preferredUID: { chosenMicrophone.current }))
        let probe = DictionaryWordProbe(speech: speechEngine, dictionary: [entry])
        showWordTrial(DictionaryTrial(subject: subject, phase: .listening))
        wordTrialWork = Task { [weak self] in
            let checking = Task { [weak self] in
                try await Task.sleep(for: DictionaryWordProbe.listeningLimit)
                self?.showWordTrial(DictionaryTrial(subject: subject, phase: .checking))
            }
            defer { checking.cancel() }
            let phase: DictionaryTrial.Phase
            do {
                let outcome = try await probe.probe(listeningTo: microphone, for: entry).outcome
                phase = .result(line: outcome.resultLine, offer: outcome.sayItLikeOffer)
            } catch let error as AudioCaptureError {
                phase = .failed(error.userMessage)
            } catch let error as SpeechEngineError {
                phase = .failed(error.userMessage)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            checking.cancel()
            self?.showWordTrial(DictionaryTrial(subject: subject, phase: phase))
        }
    }

    /// Draws a try's progress or result on the Dictionary page.
    private func showWordTrial(_ trial: DictionaryTrial) {
        wordTrial = trial
        redrawPages([.dictionary])
    }

    /// Stops a try under way, discarding its clip, and clears its result row.
    private func endWordTrial() {
        wordTrialWork?.cancel()
        wordTrialWork = nil
        guard wordTrial != nil else { return }
        wordTrial = nil
        redrawPages([.dictionary])
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

    /// Respells the word a draft duplicates, closing the editor only once it is in, as saving does.
    private func replaceWord(_ id: UUID, with word: String, pronunciation: String) {
        intentWork = Task { [weak self] in
            guard let self else { return }
            do throws(DictionaryStoreError) {
                try await dictionary.replace(id, word: word, pronunciation: pronunciation)
                editWord(nil)
            } catch {
                Self.log.error("could not replace word: \(error.userMessage, privacy: .public)")
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
        measureSnippetArrival()
        refreshMainWindow()
    }

    /// Runs the open draft's trigger through dictation's own cleaning, so the editor can say what the matcher will see.
    private func measureSnippetArrival() {
        snippetArrivalWork?.cancel()
        guard let trigger = snippetDraft?.trigger, !trigger.isEmpty, let pipeline else { return }
        guard snippetArrival?.trigger != trigger else { return }
        snippetArrivalWork = Task { [weak self] in
            let arrives = await pipeline.arrival(ofSpoken: trigger)
            guard let self, !Task.isCancelled, snippetDraft?.trigger == trigger else { return }
            snippetArrival = SnippetArrival(trigger: trigger, arrives: arrives)
            redrawPages([.snippets])
        }
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
        if updated.clipboardRetentionDays != previous.clipboardRetentionDays
            || updated.transcriptRetentionDays != previous.transcriptRetentionDays
        {
            sweepExpired()
        }
        settingsPage.synchronize(settings: updated)
        recordingSounds?.apply(updated)
        chosenMicrophone.apply(updated)
        applyAppearance()
        applyLaunchAtLogin()

        // Acted on here, or the shortcut relabels itself and the old key keeps working.
        if updated.hotkey != previous.hotkey || updated.dictationEnabled != previous.dictationEnabled
            || updated.shortcuts.first(for: .editCommand) != previous.shortcuts.first(for: .editCommand)
        {
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
        let moment = Date()
        if menuBarFeatures(for: updated, at: moment) != menuBarFeatures(for: previous, at: moment) {
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
        if updated.handsFreeDoubleTapMilliseconds != previous.handsFreeDoubleTapMilliseconds {
            Task { [weak self] in
                await self?.controller?.setDoubleTapWindow(
                    .milliseconds(updated.handsFreeDoubleTapMilliseconds))
            }
        }
        if updated.handsFreeHoldMilliseconds != previous.handsFreeHoldMilliseconds {
            Task { [weak self] in
                await self?.controller?.setMinimumHold(
                    .milliseconds(updated.handsFreeHoldMilliseconds))
            }
        }
        telemetry?.setEnabled(updated.sharesUsageStatistics)
        // As above: a switch that drew itself and changed nothing.
        if updated.installsUpdatesAutomatically != previous.installsUpdatesAutomatically {
            updates.setInstallsAutomatically(updated.installsUpdatesAutomatically)
        }
        if updated.checksForUpdatesAutomatically != previous.checksForUpdatesAutomatically {
            updates.setChecksAutomatically(updated.checksForUpdatesAutomatically)
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

    /// Whether the floating button is on screen: the setting asks for it, somebody is signed in, and windows draw.
    private var showsTheFloatingButton: Bool { surfaces.showsTheFloatingButton && drawsWindows }

    /// Shows the floating button when the setting asks for it and somebody is signed in, and hides it otherwise.
    private func showTheFloatingButtonIfWanted() {
        // Where a failure is placed depends on whether the button is there to carry it.
        defer { refreshMenuBar() }
        guard showsTheFloatingButton else { return dock.hide() }
        dock.setAnchor(settings.floatingButtonAnchor)
        dock.show()
    }

    /// A dictation's activity and failure in the menu's vocabulary, placed by which surfaces are shown.
    nonisolated static func menuBarDictation(
        for state: DictationState, floatingButtonShown: Bool
    ) -> MenuBarState {
        let activity: DictationActivity =
            switch state {
            case .idle, .failed: .idle
            case .discarded: .discarded
            case .recording: .listening
            case .transcribing, .tidying, .inserting: .working
            case .inserted(let outcome):
                DictationActivity.completion(
                    method: outcome.method, arrival: outcome.arrival, missedPieces: outcome.missedPieces)
            }
        var failure: FailurePresentation?
        if case .failed(let notice) = state {
            failure = FailurePresenter.present(
                message: notice.message, recovery: notice.recovery, severity: notice.severity,
                floatingButtonShown: floatingButtonShown)
        }
        return MenuBarState(activity: activity, failure: failure)
    }

    /// Whether the floating button collapses to a grip when idle, as the running button has it now.
    var dockShrinksToGrip: Bool { dock.shrinksToGrip }

    /// Minimises the main window while the user speaks; it stays in the Dock until the user opens it.
    private func getOutOfTheWay(for state: DictationState) {
        guard settings.minimisesWhileDictating, case .recording = state else { return }
        mainWindow?.minimise()
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

    /// Adopts macOS's current login-item state after the user may have changed it in System Settings.
    private func synchronizeLaunchAtLoginWithSystem() {
        let isEnabled = loginItem.isEnabled
        guard settings.opensAtLogin != isEnabled else { return }
        settings.opensAtLogin = isEnabled
        settingsStore.save(settings)
        settingsPage.synchronize(settings: settings)
    }

    /// How long a finished state stays up, or `nil` for a state that is not finished.
    static func linger(after state: DictationState, voiceOverEnabled: Bool = false) -> Duration? {
        switch state {
        // Copied rather than typed asks the user to paste, so it stays as long as a failure.
        case .inserted(let outcome) where outcome.method == .clipboard: failureLingers
        case .inserted: successLingers
        // An informational notice asks nothing of the user, so it goes sooner.
        case .failed(let notice):
            if notice.severity == .informational {
                successLingers
            } else if voiceOverEnabled, notice.recovery != nil {
                voiceOverFailureLingers
            } else {
                failureLingers
            }
        // A Restore on offer stays as long as a failure's button; with nothing to offer it goes sooner.
        case .discarded(let discard): discard.keptRecording == nil ? successLingers : failureLingers
        case .idle, .recording, .transcribing, .tidying, .inserting: nil
        }
    }

    /// Returns the interface to rest once the user has had time to read the result.
    private func scheduleDismissal(after state: DictationState) {
        dismissalTask?.cancel()
        dismissalCountdown = nil
        guard
            let linger = Self.linger(
                after: state, voiceOverEnabled: NSWorkspace.shared.isVoiceOverEnabled)
        else { return }
        let now = ContinuousClock.now
        dismissalCountdown = DismissalCountdown(linger, at: now)
        guard !dockHasAttention else {
            dismissalCountdown?.pause(at: now)
            return
        }
        startDismissalTimer()
    }

    private func dockAttentionChanged(to isAttended: Bool) {
        guard dockHasAttention != isAttended else { return }
        dockHasAttention = isAttended
        let now = ContinuousClock.now
        if isAttended {
            if dismissalCountdown?.hasExpired(at: now) == true {
                Task { await pipeline?.acknowledge() }
                return
            }
            dismissalCountdown?.pause(at: now)
            dismissalTask?.cancel()
            dismissalTask = nil
        } else {
            dismissalCountdown?.resume(at: now)
            startDismissalTimer()
        }
    }

    private func startDismissalTimer() {
        guard let remaining = dismissalCountdown?.remaining, remaining > .zero else { return }
        dismissalTask = Task { [weak self] in
            do { try await Task.sleep(for: remaining) } catch { return }
            guard let self, !self.dockHasAttention,
                self.dismissalCountdown?.hasExpired(at: ContinuousClock.now) == true
            else { return }
            await self.pipeline?.acknowledge()
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
        case .copyTranscript:
            if case .failed(let failure) = lastDictationState, let text = failure.wordsToKeep {
                putOnClipboard(text, concealed: DictationTextPresentation(text).isSecret, used: nil)
            }
            Task { await pipeline?.acknowledge() }
        case .showHistory:
            // Delivery was unconfirmed or the clipboard failed; History lists every kept dictation.
            show(.main(.history))
            Task { await pipeline?.acknowledge() }
        case .retryFromRecording:
            // History's Retry, run from the notice, so the words reach the clipboard in one press.
            if case .failed(let failure) = lastDictationState, let id = failure.keptRecording {
                carryOut(MainIntent.retryRecording(id))
            } else {
                show(.main(.history))
                Task { await pipeline?.acknowledge() }
            }
        case .restoreRecording:
            // The same retry, run on the recording a cancel kept, so its words reach the clipboard.
            if case .discarded(let discard) = lastDictationState, let id = discard.keptRecording {
                carryOut(MainIntent.retryRecording(id))
            } else {
                Task { await pipeline?.acknowledge() }
            }
        }
    }

    private func openSettingsPane(_ pane: SystemSettingsPane) async {
        switch pane {
        case .accessibility:
            let outcome = await AccessibilityPermissionGate().request()
            if outcome == .granted {
                startWatchingForTheShortcut()
            }
        case .microphone:
            _ = await MicrophonePermissionGate().requestOrOpenSettings()
        case .appleIntelligence:
            SystemSettingsOpener().open(.appleIntelligence)
        case .keyboard, .soundInput:
            SystemSettingsOpener().open(pane)
        }
    }
}

// MARK: - The pipeline's seams, wired to the real stores

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
            }, caret: expansion.caret)
    }
}

/// Gives one retry exclusive ownership of the history badge until it finishes.
@MainActor
final class RetryBadgeOwnership {
    private(set) var recording: UUID?

    /// Refuses to transfer an in-flight retry's badge to a later click.
    func begin(_ id: UUID) -> Bool {
        guard recording == nil else { return false }
        recording = id
        return true
    }

    /// Finishes only the retry that currently owns the badge.
    @discardableResult
    func finish(_ id: UUID) -> Bool {
        guard recording == id else { return false }
        recording = nil
        return true
    }

    func clear() { recording = nil }
}

/// A menu is built from a snapshot, so an index that has gone stale must do nothing.
extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
