import AppKit
import Foundation
import OSLog
import UttrflowContext
import UttrflowCore
import UttrflowInput
import UttrflowPredict
import UttrflowPredictCapture
import UttrflowPredictStore

private struct SuggestionSessionEndObservers {
    let workspaceCenter: NotificationCenter
    let workspaceObservers: [any NSObjectProtocol]
    let screenLockCenter: NotificationCenter
    let screenLockObserver: any NSObjectProtocol

    func remove() {
        for observer in workspaceObservers { workspaceCenter.removeObserver(observer) }
        screenLockCenter.removeObserver(screenLockObserver)
    }
}

@MainActor
protocol SuggestionProcessActivityManaging {
    func begin()
    func end()
}

@MainActor
private final class ProcessSuggestionActivity: SuggestionProcessActivityManaging {
    private var activity: (any NSObjectProtocol)?

    func begin() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Keeps typing suggestions responsive while the app is in the background.")
    }

    func end() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }
}

/// Starts a check of the focused selection repeating at `interval` and returns what stops it.
typealias SelectionCheckScheduling =
    @MainActor (
        _ interval: TimeInterval, _ check: @escaping @MainActor () -> Void
    ) -> @MainActor () -> Void

/// Runs tab-to-complete end to end: reads the field, asks the corpus, draws, accepts, records.
@MainActor
final class SuggestionCoordinator {
    enum AccessibilityValueChangeAction: Equatable {
        case ignore
        case wake
        case withdrawAndWake
    }

    /// Says why nothing is being suggested, which silence alone cannot.
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "predict")

    let store: PredictStore
    private let rejectedSuggestionRecorder: RejectedSuggestionRecorder
    let capture: CaptureSession
    private let panel: SuggestionPanelController
    private let interceptor = KeyInterceptor()
    private let secureInput: SecureInputWatch
    /// Whether secure keyboard entry is holding suggestions off, as this coordinator last saw it.
    var isSecureInputBlocking: Bool { secureInput.isBlocking }
    private let acceptor: SuggestionAcceptor
    let focusedFieldValueObserver: any FocusedFieldValueObserving
    /// Keeps background typing work responsive for the coordinator's lifetime.
    private let processActivity: any SuggestionProcessActivityManaging
    /// What the user has decided on the Suggestions screen, which the app hands over as it changes.
    private(set) var preferences: SuggestionPreferences
    /// Whether a native menu currently owns keyboard gestures in the focused application.
    private var nativeMenuIsOpen = false
    /// What exists on this machine right now, which the corpus cannot know. See `Docs/predict.md`.
    private let environment: EnvironmentSource
    /// The gates that decide whether a candidate is right, which is not what the ranking measures.
    private let verifier: Verifier
    /// The model that invents a suggestion when the corpus has none, absent until the app hands one over.
    private let generator: (any CandidateGenerating)?
    /// Reads only focus identity and selection while a completion is armed.
    private let focusedSelectionReader: @Sendable () async -> FocusedFieldSelectionRead
    /// Reads the whole focused field, the one cross-process read a turn makes.
    private let focusedFieldReader: @Sendable () async -> FocusedFieldSnapshot?
    /// The frontmost application's bundle identifier, which decides whether a key or a turn is acted on.
    let frontmostBundleIdentifier: @MainActor () -> String?
    /// What the model last answered or had nothing for, which decides whether it is asked again.
    private var modelPass = ModelPass()
    /// The model pass in flight, cancelled by the next keystroke so a burst never queues one pass per key.
    var generating = GeneratingTaskSlot()
    /// A turn booked for the moment a rule stops refusing, so a prose pause is answered then, not at the next tick.
    private var pendingWake: Task<Void, Never>?
    /// Distinguishes the latest delayed wake from a canceled task that just finished sleeping.
    private var pendingWakeGeneration = 0
    /// The restart booked after macOS disabled the tap, cancelled by `stop()` so a turned-off tap stays off.
    let tapRest = TapRest()
    /// The turn in flight, cancelled by the next keystroke so its scoring stops rather than running past the line it was for.
    private var running: Task<Void, Never>?
    /// How long a burst of keystrokes must pause before the model is asked about its last prefix.
    nonisolated static let generationDebounceInMilliseconds = 120
    /// How long typing must pause before a field snapshot may begin.
    nonisolated static let fieldReadDebounceInMilliseconds = 180
    /// Lets the target application apply a drop before its field is read again.
    nonisolated static let mouseUpReadDelayInMilliseconds = 80
    /// How long a key-down can explain an Accessibility value change.
    nonisolated static let accessibilityKeyWindowInMilliseconds = 100

    var session = SuggestionSession()
    private var monitors: [Any] = []
    /// The scroll monitor, present only while a ghost is drawn, since a scroll matters only then.
    private var scrollMonitor: Any?
    private var activationMonitor: SuggestionActivationMonitor?
    private var activityIsWatched = false
    /// Starts the repeating selection check and returns what stops it, so a test decides when each check runs.
    private let scheduleSelectionChecks: SelectionCheckScheduling
    /// Stops the selection check, present only while a ghost can still be accepted.
    private var stopSelectionChecks: (@MainActor () -> Void)?
    /// The cadence the running selection check was scheduled at.
    private var selectionCheckInterval: TimeInterval?
    private var selectionGuard: ArmedSelectionGuard?
    private var selectionPollInFlight = false
    private var selectionPollGeneration = 0
    private var activations: (any NSObjectProtocol)?
    private var sessionEndObservers: SuggestionSessionEndObservers?
    /// The Space and sleep observers, each of which leaves a ghost with no field under it.
    private var spaceObservers: [any NSObjectProtocol] = []
    /// Whether a held mouse button can still move the focused window under a ghost.
    private var isPointerGestureActive = false
    private var ticker: Timer?
    /// Polls secure keyboard entry while it pauses suggestions, since no key or field event arrives to end the pause.
    private var secureInputRecheck: Timer?
    /// Whether field observation is active or kept alive by a visible ghost.
    private var ticking = SuggestionTicking()
    private var swallowed: Task<Void, Never>?
    /// Closing punctuation already present after the caret of the current offer.
    private var closingPunctuationAfterCaret = ""
    /// The line the accept key takes as last armed by a draw, so a later answer never inherits that claim.
    private(set) var armedOffer: String?
    var isSelectionPolling: Bool { stopSelectionChecks != nil }
    var isTickerScheduled: Bool { ticker != nil }
    var isSecureInputRecheckScheduled: Bool { secureInputRecheck != nil }
    private var lastKeystroke = Date.distantPast
    private var lastFluentKeystroke = Date.distantPast
    /// The last observed key-down, used to distinguish typing from edits made without a key.
    private var lastObservedKeyDown = Date.distantPast
    /// One turn at a time, with a turn that never returns left behind so the loop cannot die with it.
    var turns = TurnGate()
    /// How many turns have run or are running, so a test can hold each turn to one field read.
    var turnsAdmitted: Int { turns.admitted }
    /// Whether no turn is running and none is booked, so a test knows every key it sent has been answered.
    var isSettled: Bool { !turns.isRunning && pendingWake == nil }
    /// The step the newest turn is waiting on and the bundle identifier it read, so a stall names where it stuck.
    private var progress: (turn: Int, step: SuggestionTurnStep, application: String)?
    /// What this turn has already been told about the moment, so one line costs one walk.
    private let contextCache = SuggestionContextCache()
    /// True while an accepted completion is being inserted, so the keys it posts wake no further turn.
    private var isInserting = false
    /// Holds the pending wake and stopped state, so stop discards work a turn had queued.
    private var wakeState = SuggestionWakeState()
    private var runningTurn: Int?
    var isActiveForUpdate: Bool {
        !wakeState.isStopped
            && (ticking.isRunning || armedOffer != nil || generating.turn != nil || runningTurn != nil)
    }
    /// Set while a dictation is under way, when no turn may start.
    private var isDictating = DictationInProgress.shared.isDictating
    /// Whether the last field read reported marked text, so a Return next confirms a conversion rather than ending the line.
    private var composingAtLastRead = false
    /// The accepted lines still being written to the corpus, which a held key never waits on.
    let acceptances: AcceptanceQueue
    /// What capture is told about the focused field between reads, and in which order.
    let captureFeed: SuggestionCaptureFeed
    let ownBundleIdentifier = Bundle.main.bundleIdentifier
    /// Called when the user turns the feature off everywhere, so the choice is persisted and can be undone.
    var onTurnedOffEverywhere: (() -> Void)?
    var onConsentPersistenceFailure: ((any Error) -> Void)?
    /// Tells the menu bar why suggestion input is paused.
    var onSecureInputBlockingChanged: ((Bool) -> Void)?
    var onTapRestChanged: ((Result<Void, any Error>?) -> Void)?
    /// Marks the short transition from a completed rest to an attempted tap restart.
    var onTapRestRestarting: (() -> Void)?
    var onSecureInputChanged: ((Bool) -> Void)?

    /// Runs synchronous store opening away from the main actor before the suggestion loop is assembled.
    nonisolated static func startupFileWorkOffMain<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await Task.detached(priority: .utility, operation: operation).value
    }

    /// Opens the corpus, or reports why it could not; the scorer, when given, is the model that validates.
    init(
        container: URL, preferences: SuggestionPreferences,
        scoring: (any CandidateScoring)? = nil, generating: (any CandidateGenerating)? = nil,
        encryptedStore: EncryptedStore? = nil,
        captureSink: (any CaptureSink)? = nil,
        environmentIndex: EnvironmentIndex? = nil,
        focusedFieldValueObserver: (any FocusedFieldValueObserving)? = nil,
        processActivity: any SuggestionProcessActivityManaging = ProcessSuggestionActivity(),
        secureInput: SecureInputWatch = SecureInputWatch(),
        onCaptureSkipped: (@Sendable (CaptureSkipReason) async -> Void)? = nil,
        focusedSelectionReader: @escaping @Sendable () async -> FocusedFieldSelectionRead = {
            await FocusedFieldReader.focusedSelection()
        },
        focusedFieldReader: @escaping @Sendable () async -> FocusedFieldSnapshot? = {
            await FocusedFieldReader.read()
        },
        frontmostBundleIdentifier: @escaping @MainActor () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        },
        scheduleSelectionChecks: @escaping SelectionCheckScheduling = SuggestionCoordinator.selectionTimer,
        panel: SuggestionPanelController = .shared,
        editHeard: @escaping @Sendable (EditedSpan) async -> Void = { _ in }
    ) async throws {
        self.preferences = preferences
        self.processActivity = processActivity
        self.secureInput = secureInput
        self.generator = generating
        self.focusedSelectionReader = focusedSelectionReader
        self.focusedFieldReader = focusedFieldReader
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.scheduleSelectionChecks = scheduleSelectionChecks
        self.panel = panel
        self.focusedFieldValueObserver = focusedFieldValueObserver ?? FocusedFieldValueObserver()
        let storePath = PredictStore.defaultFile(in: container).path(percentEncoded: false)
        let preferencesPath =
            CapturePreferencesFile.defaultFile(in: container).path(percentEncoded: false)
        let (store, capturePreferences) = try await Self.startupFileWorkOffMain {
            let store = try PredictStore(path: storePath, encryptedStore: encryptedStore)
            let preferences = CapturePreferencesFile(path: preferencesPath).load()
            return (store, preferences)
        }
        self.store = store
        rejectedSuggestionRecorder = RejectedSuggestionRecorder(store: store)
        // Lines learned before the credential rules last widened are removed once, off the typing path.
        Task.detached(priority: .utility) { _ = try? await CaptureGate.sweepSecrets(from: store) }
        // One index behind both, so asking the machine for a completion also warms what attests it.
        let index = environmentIndex ?? EnvironmentIndex(reader: SystemEnvironmentReader())
        environment = EnvironmentSource(index: index)
        // The model, when the app hands one over, is what turns a habit into a validated suggestion.
        verifier = Verifier(index: index, scoring: scoring, supersession: store)
        let capture = CaptureSession(
            sink: captureSink ?? EditHearingSink(store: store, heard: editHeard),
            preferencesFile: CapturePreferencesFile(
                path: CapturePreferencesFile.defaultFile(in: container).path(percentEncoded: false)),
            initialPreferences: capturePreferences,
            // A line that was never sent was not a value: a shell and a chat composer learn on Return alone.
            policy: .whereReturnSends, onCommitSkipped: onCaptureSkipped)
        self.capture = capture
        let acceptances = AcceptanceQueue { await capture.abandonFocusedField() }
        self.acceptances = acceptances
        captureFeed = SuggestionCaptureFeed(capture: capture, acceptances: acceptances)
        acceptor = SuggestionAcceptor(completion: TextInsertion.completion(), focus: AXAccessibilityFocus())
    }

    isolated deinit {
        stop()
    }

    /// Takes what the user has just chosen, so a change on the Suggestions screen holds from the next keystroke.
    func follow(_ preferences: SuggestionPreferences) {
        let moment = Date()
        let before = self.preferences
        self.preferences = preferences
        refreshFocusedFieldObservation()
        if Self.disablesSuggestions(
            in: frontmostBundleIdentifier(),
            before: before, after: preferences, at: moment)
        {
            withdraw()
            stopTicker()
        }
        // One switch, two stores: what may be suggested in is what may be learned from. See `Docs/predict.md`.
        Task { [capture, onConsentPersistenceFailure] in
            await SuggestionConsentPersistence.recordChanges(
                from: before, to: preferences, using: capture, onFailure: onConsentPersistenceFailure)
        }
    }

    /// Whether one update turns off suggestions for the application currently holding the field.
    nonisolated static func disablesSuggestions(
        in bundleIdentifier: String?, before: SuggestionPreferences, after: SuggestionPreferences,
        at moment: Date
    ) -> Bool {
        guard let bundleIdentifier else { return before.isEnabled && !after.isEnabled }
        return before.isEnabled(in: bundleIdentifier, at: moment)
            && !after.isEnabled(in: bundleIdentifier, at: moment)
    }

    /// Forgets every answer about which applications may be learned from, which a reset asks for.
    func forgetEveryAnswer() async throws {
        try await capture.forgetEveryAnswer()
    }

    /// The newest lines the user types in one application, which the dictionary reads for sightings. See Docs/app-dictionary.md.
    func typedLines(in bundleIdentifier: String) async -> [String] {
        (try? await store.recentLines(inApplication: bundleIdentifier, limit: Self.typedLinesForSightings))
            ?? []
    }

    /// How many typed lines one dictation reads for sightings, enough for a working session's names.
    static let typedLinesForSightings = 32

    /// Forgets what one application taught, on disk and in every copy this loop holds.
    func forgetSuggestions(from bundleIdentifier: String) async throws {
        let capture = self.capture
        let store = self.store
        try await forgetWhatThisLoopRemembers(
            of: bundleIdentifier,
            clearingCorpus: {
                await capture.forgetLearned(from: bundleIdentifier)
                try await store.forget(bundleIdentifier: bundleIdentifier)
            })
    }

    /// Forgets every line and answer, on disk and in every copy this loop holds.
    func forgetEverySuggestion() async throws {
        let capture = self.capture
        let store = self.store
        try await forgetWhatThisLoopRemembers(
            of: nil,
            clearingCorpus: {
                await capture.forgetLearnedLines()
                try await store.forgetEverything()
                try await capture.forgetEveryAnswer()
            })
    }

    /// Drops the verdicts, model answers and held rejections this loop keeps for one application, or for all when nil.
    private func forgetWhatThisLoopRemembers(
        of bundleIdentifier: String?, clearingCorpus: @escaping @Sendable () async throws -> Void
    ) async throws {
        rejectedSuggestionRecorder.forget(bundleIdentifier: bundleIdentifier)
        await acceptances.beginForgetting()
        defer { acceptances.finishForgetting() }
        try await verifier.forgetEverything(then: clearingCorpus)
        modelPass.freshStart(surfaceChanged: true, lineIsEmpty: true)
    }

    /// Arms the tap and starts watching, or says why it cannot.
    @discardableResult
    func start() -> Result<Void, any Error> {
        FocusedFieldReader.beginFullTreeSession()
        processActivity.begin()
        wakeState.start()
        tapRest.cancel()
        activationMonitor = SuggestionActivationMonitor { [weak self] trust in
            guard let self else { return }
            let wasSecureInputBlocking = self.secureInput.isBlocking
            self.checkSecureInput()
            guard !self.secureInput.isBlocking else { return }
            guard trust != .denied else {
                self.tapRest.cancel()
                self.withdraw()
                for monitor in self.monitors { NSEvent.removeMonitor(monitor) }
                self.monitors = []
                self.activityIsWatched = false
                self.stopWatchingScrolls()
                self.stopWatchingSelection()
                self.focusedFieldValueObserver.stop()
                self.interceptor.stop()
                if let activations = self.activations {
                    NSWorkspace.shared.notificationCenter.removeObserver(activations)
                    self.activations = nil
                }
                for observer in self.spaceObservers {
                    NSWorkspace.shared.notificationCenter.removeObserver(observer)
                }
                self.spaceObservers = []
                self.sessionEndObservers?.remove()
                self.sessionEndObservers = nil
                self.onTapRestChanged?(.failure(KeyInterceptorFailure.accessibilityDenied))
                return
            }
            self.refreshFocusedFieldObservation()
            self.applicationChanged(front: self.frontmostBundleIdentifier())
            guard !wasSecureInputBlocking else { return }
            guard trust == .granted else { return }
            switch self.startInterceptor() {
            case .success: self.onTapRestChanged?(.success(()))
            case .failure(let error): self.onTapRestChanged?(.failure(error))
            }
        }
        activationMonitor?.start()
        checkSecureInput()
        guard !secureInput.isBlocking else {
            onSecureInputChanged?(true)
            return .success(())
        }
        let result = startInterceptor()
        if case .success = result { onTapRestChanged?(.success(())) }
        return result
    }

    /// Starts the key tap and activity monitors after secure keyboard entry ends.
    private func startInterceptor() -> Result<Void, any Error> {
        do {
            try interceptor.start()
        } catch {
            Self.log.error("tab-to-complete is off: \(SuggestionLog.failure(error), privacy: .public)")
            return .failure(error)
        }
        interceptor.arm([])
        // Before the first keystroke, because the reader's queue may not call AppKit or HIToolbox.
        FocusedFieldReader.prepare()
        // A ghost the panel takes off screen on its own, when it grows past its room, gives up its keys too.
        panel.onWithdrawnUnasked = { [weak self] in
            self?.stopWatchingSelection()
            self?.interceptor.arm([])
            self?.armedOffer = nil
        }
        watchSwallowedKeys()
        if !activityIsWatched {
            watchForActivity()
            activityIsWatched = true
        } else {
            watchFocusedFieldValues()
        }
        return .success(())
    }

    /// Withdraws suggestions while secure keyboard entry prevents reliable key capture.
    private func checkSecureInput() {
        guard secureInput.check() else { return }
        let now = secureInput.isBlocking ? "on" : "off"
        Self.log.notice("suggestion secure keyboard entry \(now, privacy: .public)")
        if secureInput.isBlocking {
            onSecureInputChanged?(true)
            // A rest ending now would bring the tap back into the secure entry it was withdrawn from.
            tapRest.cancel()
            withdraw()
            focusedFieldValueObserver.stop()
            interceptor.stop()
            onSecureInputBlockingChanged?(true)
            panel.announce(SecureInputWatch.suggestionNotice)
            scheduleSecureInputRecheck()
        } else {
            stopSecureInputRecheck()
            onSecureInputChanged?(false)
            onSecureInputBlockingChanged?(false)
            switch startInterceptor() {
            case .success: onTapRestChanged?(.success(()))
            case .failure(let error): onTapRestChanged?(.failure(error))
            }
        }
    }

    /// Rechecks secure keyboard entry on a timer, so the pause lifts in the same app without an activation.
    private func scheduleSecureInputRecheck() {
        guard secureInputRecheck == nil, !wakeState.isStopped else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: SuggestionTicking.interval, repeats: true) {
            [weak self] _ in MainActor.assumeIsolated { self?.checkSecureInput() }
        }
        timer.tolerance = SuggestionTicking.tolerance
        secureInputRecheck = timer
    }

    private func stopSecureInputRecheck() {
        secureInputRecheck?.invalidate()
        secureInputRecheck = nil
    }

    /// Takes the surface away, disarms the tap and stops watching.
    func stop() {
        stopSecureInputRecheck()
        processActivity.end()
        wakeState.stop()
        turns.abandon()
        runningTurn = nil
        nativeMenuIsOpen = false
        onSecureInputBlockingChanged?(false)
        tapRest.cancel()
        session.invalidate()
        interceptor.arm([])
        interceptor.stop()
        panel.hide()
        swallowed?.cancel()
        swallowed = nil
        generating.cancel()
        cancelPendingWake()
        running?.cancel()
        captureFeed.discard()
        ticker?.invalidate()
        ticker = nil
        ticking = SuggestionTicking()
        isPointerGestureActive = false
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        stopWatchingScrolls()
        activationMonitor?.stop()
        activationMonitor = nil
        activityIsWatched = false
        stopWatchingSelection()
        if let activations { NSWorkspace.shared.notificationCenter.removeObserver(activations) }
        activations = nil
        sessionEndObservers?.remove()
        sessionEndObservers = nil
        for observer in spaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        spaceObservers = []
        focusedFieldValueObserver.stop()
        // A browser's full Accessibility tree stays on only while suggestions do.
        FocusedFieldReader.releaseFullTrees()
    }

    /// Waits for an accepted line's corpus write and the typed fallback's posted replacement to finish.
    func finishWrites() async {
        await acceptances.drained()
        await acceptor.finishWrites()
    }

    // MARK: What wakes the loop

    /// Keystrokes elsewhere, the application in front changing, and a clock for the pauses.
    private func watchForActivity() {
        watchFocusedFieldValues()
        observeSessionEnd(
            in: NSWorkspace.shared.notificationCenter,
            screenLockCenter: DistributedNotificationCenter.default())
        let keys = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let pastes = Self.isPaste(event)
            let observedAt = Date()
            // A key this app inserted must not wake another turn, or the feature types on its own.
            if let cgEvent = event.cgEvent, SyntheticEvent.isOurs(cgEvent) { return }
            let text = Self.typedText(characters: event.characters, modifiers: event.modifierFlags)
            guard let self else { return }
            MainActor.assumeIsolated {
                // Excluded and unknown applications should not accumulate capture state between turns.
                guard
                    Self.shouldProcessActivityEvent(
                        front: self.frontmostBundleIdentifier(),
                        own: self.ownBundleIdentifier, preferences: self.preferences, at: observedAt)
                else { return }
                // A paste, the person's or this app's own, puts words in the line that were never typed.
                self.lastObservedKeyDown = observedAt
                if pastes { self.captureFeed.noteInsertion() }
                if !pastes {
                    if let text {
                        self.queueCaptureTyping(
                            text, from: self.frontmostBundleIdentifier(),
                            at: observedAt)
                    } else if Key(keyCode: event.keyCode) != .return {
                        self.queueCaptureTyping(
                            nil, from: self.frontmostBundleIdentifier(),
                            at: observedAt)
                    }
                }
                if Self.mayMoveFocus(keyCode: event.keyCode, modifiers: event.modifierFlags) {
                    FocusedFieldReader.focusMayHaveMoved()
                } else {
                    FocusedFieldReader.fieldMayHaveChanged()
                }
                self.keyPressed(Key(keyCode: event.keyCode), typing: text, isARepeat: event.isARepeat)
            }
        }
        if let keys { monitors.append(keys) }
        // A mouse-up can finish a text drop, so withdraw then read after the target applies it.
        let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) {
            [weak self] event in
            let delay = event.type == .leftMouseUp ? Self.mouseUpReadDelayInMilliseconds : 0
            FocusedFieldReader.focusMayHaveMoved()
            MainActor.assumeIsolated {
                if event.type == .leftMouseDown {
                    self?.isPointerGestureActive = true
                } else if event.type == .leftMouseUp {
                    self?.isPointerGestureActive = false
                }
                guard let self else { return }
                let shouldProcess = self.activityIsAllowed()
                self.refreshFocusedFieldObservation()
                self.withdraw()
                guard shouldProcess else { return }
                self.noteActivity()
                if delay > 0 {
                    self.wake(.tick, afterMilliseconds: delay)
                } else {
                    self.wake(.tick)
                }
            }
        }
        if let clicks { monitors.append(clicks) }
        activations = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                let activeProcessIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier
                FocusedFieldReader.releaseFullTrees(except: activeProcessIdentifier)
                self?.refreshFocusedFieldObservation()
                self?.applicationChanged(front: self?.frontmostBundleIdentifier())
            }
        }
        for name in [NSWorkspace.activeSpaceDidChangeNotification] {
            spaceObservers.append(
                NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in MainActor.assumeIsolated { self?.withdraw() }
                })
        }
    }

    func observeSessionEnd(in workspaceCenter: NotificationCenter, screenLockCenter: NotificationCenter) {
        guard sessionEndObservers == nil else { return }
        let onEnd: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.endSessionObservation() }
        }
        sessionEndObservers = SuggestionSessionEndObservers(
            workspaceCenter: workspaceCenter,
            workspaceObservers: DictationSessionEndObserver.observe(in: workspaceCenter, onEnd: onEnd),
            screenLockCenter: screenLockCenter,
            screenLockObserver: DictationSessionEndObserver.observeScreenLock(
                in: screenLockCenter, onEnd: onEnd))
    }

    private func endSessionObservation() {
        ticker?.invalidate()
        ticker = nil
        ticking = SuggestionTicking()
        withdraw()
    }

    func watchFocusedFieldValues() {
        focusedFieldValueObserver.start(
            for: focusedFieldObservationTarget(),
            onValueChanged: { [weak self] in self?.accessibilityValueChanged() },
            onNativeMenuVisibilityChanged: { [weak self] isOpen in
                guard let self else { return }
                nativeMenuIsOpen = isOpen
                interceptor.setNativeMenuIsOpen(isOpen)
                if isOpen {
                    withdraw()
                } else if !wakeState.isStopped, !secureInput.isBlocking,
                    Self.shouldProcessActivityEvent(
                        front: frontmostBundleIdentifier(),
                        own: ownBundleIdentifier, preferences: preferences, at: Date())
                {
                    wake(.tick)
                }
            })
    }

    /// Withdraws an offer when the focused field changes without a corresponding key event.
    private func accessibilityValueChanged() {
        guard !wakeState.isStopped, !isInserting else { return }
        guard
            Self.shouldProcessActivityEvent(
                front: frontmostBundleIdentifier(),
                own: ownBundleIdentifier, preferences: preferences, at: Date())
        else {
            stopTicker()
            return
        }
        let moment = Date()
        // A slow field echoes typed keys late; capture checks that change against the keys instead.
        if Self.isUnkeyedAccessibilityChange(lastKeyDown: lastObservedKeyDown, at: moment),
            !captureFeed.awaitsTypedEcho
        {
            captureFeed.noteInsertion()
        }
        let action = Self.accessibilityValueChangeAction(
            hasArmedOffer: armedOffer != nil, lastKeystroke: lastKeystroke, at: moment)
        guard action != .ignore else { return }
        noteActivity()
        if action == .withdrawAndWake { withdraw() }
        wake(.tick)
    }

    /// A late value change schedules the first turn even without a ghost; only an armed ghost can be withdrawn.
    nonisolated static func accessibilityValueChangeAction(
        hasArmedOffer: Bool, lastKeystroke: Date, at moment: Date
    ) -> AccessibilityValueChangeAction {
        guard hasArmedOffer else { return .wake }
        guard moment >= lastKeystroke else { return .withdrawAndWake }
        guard
            elapsedMilliseconds(since: lastKeystroke, at: moment)
                >= fieldReadDebounceInMilliseconds
        else {
            return .ignore
        }
        return .withdrawAndWake
    }

    /// Whether a value change arrived without a nearby key-down to explain it.
    nonisolated static func isUnkeyedAccessibilityChange(lastKeyDown: Date, at moment: Date) -> Bool {
        guard moment >= lastKeyDown else { return true }
        return elapsedMilliseconds(since: lastKeyDown, at: moment) >= accessibilityKeyWindowInMilliseconds
    }

    /// Elapsed key time never goes below zero when the system wall clock moves backwards.
    nonisolated static func elapsedMilliseconds(since earlier: Date, at later: Date) -> Int {
        max(0, Int(later.timeIntervalSince(earlier) * 1000))
    }

    /// Whether a key-down may move keyboard focus to another field: Tab, Escape, or any ⌘ shortcut.
    nonisolated static func mayMoveFocus(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let key = Key(keyCode: keyCode)
        return key == .tab || key == .escape || modifiers.contains(.command)
    }

    /// Whether a key-down is ⌘V under the selected layout, matched by the key its ⌘ table puts V on.
    nonisolated static func isPaste(_ event: NSEvent) -> Bool {
        isPaste(
            keyCode: event.keyCode, modifiers: event.modifierFlags,
            pasteKeyCode: CGEventKeystrokeSender.pasteKeyCode)
    }

    /// Whether a key with `modifiers` held is the layout's ⌘V, whatever letter the key types without ⌘.
    nonisolated static func isPaste(
        keyCode: UInt16, modifiers: NSEvent.ModifierFlags, pasteKeyCode: UInt16
    ) -> Bool {
        modifiers.contains(.command) && keyCode == pasteKeyCode
    }

    /// Withdraws the ghost and holds every turn while a dictation is under way, so its models have the GPU.
    func dictationChanged(isDictating: Bool) {
        guard self.isDictating != isDictating else { return }
        self.isDictating = isDictating

        // A dictation that ends leaves its words in the field, and they are not this person's typing.
        guard isDictating else {
            captureFeed.noteInsertion()
            wake(.tick)
            return
        }
        wakeState.clearQueuedWake()
        turns.abandon()
        withdraw()
    }

    /// Takes the ghost and the keys it claims away, and voids every answer in flight, because the caret may have moved under it.
    private func withdraw() {
        stopWatchingSelection()
        armedOffer = nil
        session.invalidate()
        generating.cancel()
        cancelPendingWake()
        running?.cancel()
        FocusedFieldReader.cancelRead()
        interceptor.arm([])
        panel.hide()
    }

    /// Watches scrolls while a ghost is drawn; a scroll carries the caret's line away under a ghost that stays put.
    private func watchScrolls() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrolled() }
        }
    }

    /// Stops watching scrolls, so scrolling with no ghost drawn never wakes the app.
    private func stopWatchingScrolls() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }

    /// Checks the caret only while a drawn offer can be accepted, at the clock's selection cadence.
    func armSelectionMonitor(
        for suggestion: Suggestion, at range: NSRange?, identity: FocusedFieldIdentity? = nil
    ) {
        armedOffer = suggestion.accepting
        guard armedOffer != nil else { return stopWatchingSelection() }
        stopWatchingSelection()
        selectionGuard = ArmedSelectionGuard(expectedRange: range, identity: identity)
        startSelectionChecks(every: ticking.selectionInterval)
    }

    /// Schedules the current selection check at `interval`, replacing any running one.
    private func startSelectionChecks(every interval: TimeInterval) {
        stopSelectionChecks?()
        let generation = selectionPollGeneration
        selectionCheckInterval = interval
        stopSelectionChecks = scheduleSelectionChecks(interval) { [weak self] in
            self?.pollSelection(generation: generation)
        }
    }

    /// Moves a running selection check to the clock's cadence, so an idle ghost is not read 300 times a minute.
    private func followSelectionCadence() {
        let interval = ticking.selectionInterval
        guard stopSelectionChecks != nil, selectionCheckInterval != interval else { return }
        startSelectionChecks(every: interval)
    }

    /// Runs `check` every `interval` on the main run loop and returns what stops it.
    static func selectionTimer(
        every interval: TimeInterval, _ check: @escaping @MainActor () -> Void
    ) -> @MainActor () -> Void {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { check() }
        }
        timer.tolerance = interval / 4
        return { timer.invalidate() }
    }

    /// Withdraws the offer when Accessibility reports a different selection or focused element.
    private func pollSelection(generation: Int) {
        guard generation == selectionPollGeneration else { return }
        guard activityIsAllowed() else { return withdraw() }
        Task { [weak self] in await self?.pollFocusedSelection(generation: generation) }
    }

    /// Reads the focused selection and withdraws an armed offer when it no longer matches.
    func pollFocusedSelection(generation: Int? = nil) async {
        let generation = generation ?? selectionPollGeneration
        guard generation == selectionPollGeneration, !selectionPollInFlight,
            armedOffer != nil, selectionGuard != nil, !isInserting
        else { return }
        guard activityIsAllowed() else { return withdraw() }
        selectionPollInFlight = true
        let read = await focusedSelectionReader()
        guard generation == selectionPollGeneration else { return }
        selectionPollInFlight = false
        let selection: FocusedFieldSelection
        switch read {
        case .timedOut:
            return
        case .unavailable:
            return withdraw()
        case .selection(let value):
            selection = value
        }
        guard var selectionGuard else { return }
        guard !selectionGuard.observe(selection) else { return withdraw() }
        self.selectionGuard = selectionGuard
    }

    /// Stops the selection poll and invalidates any result still waiting on Accessibility.
    private func stopWatchingSelection() {
        selectionPollGeneration += 1
        stopSelectionChecks?()
        stopSelectionChecks = nil
        selectionCheckInterval = nil
        selectionGuard = nil
        selectionPollInFlight = false
        FocusedFieldReader.cancelFocusedSelectionRead()
    }

    /// Withdraws a ghost the scroll has left behind, once, and lets the clock redraw it where the caret now is.
    private func scrolled() {
        guard panel.isShowing else { return stopWatchingScrolls() }
        guard !isInserting else { return }
        FocusedFieldReader.fieldMayHaveChanged()
        noteActivity()
        withdraw()
    }

    /// Starts the pause clock if it is not running; every activity calls this.
    func noteActivity(at moment: ContinuousClock.Instant = ContinuousClock.now) {
        guard activityIsAllowed() else {
            stopTicker()
            return
        }
        guard ticking.noteActivity(at: moment) else { return }
        scheduleTicker(every: SuggestionTicking.interval)
        followSelectionCadence()
    }

    /// Stops the activity clock when a disabled application becomes frontmost.
    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        ticking = SuggestionTicking()
    }

    /// Schedules field observation at the cadence for the current phase.
    func scheduleTicker(every interval: TimeInterval) {
        ticker?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = min(SuggestionTicking.tolerance, interval / 5)
        ticker = timer
    }

    /// Wakes a turn while a field can change beneath a visible ghost.
    func tick() {
        guard activityIsAllowed() else {
            stopTicker()
            return
        }
        switch ticking.tick(at: ContinuousClock.now, ghostIsVisible: panel.isShowing) {
        case .wake:
            wake(.tick)
        case .wakeAndSlow:
            scheduleTicker(every: SuggestionTicking.ghostInterval)
            followSelectionCadence()
            wake(.tick)
        case .stop:
            ticker?.invalidate()
            ticker = nil
        }
    }

    /// The text a key puts on the line, or nothing for a shortcut, an arrow or any other key that types no text.
    nonisolated static func typedText(characters: String?, modifiers: NSEvent.ModifierFlags) -> String? {
        guard let characters, !characters.isEmpty,
            modifiers.intersection([.command, .control, .option, .function]).isEmpty,
            characters.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
            })
        else { return nil }
        return characters
    }

    /// One key pressed in another application, which may update the focused field.
    func keyPressed(_ key: Key, typing text: String? = nil, isARepeat: Bool = false) {
        guard
            Self.shouldProcessActivityEvent(
                front: frontmostBundleIdentifier(),
                own: ownBundleIdentifier, preferences: preferences, at: Date())
        else {
            stopTicker()
            return
        }
        noteActivity()
        lastKeystroke = Date()
        lastFluentKeystroke = Self.fluencyTimestamp(
            previous: lastFluentKeystroke, typing: text, isARepeat: isARepeat, at: Date())
        if let text, typedThrough(text) { return }
        // Counted in the session, so a Tab pressed before the next read cannot take an offer for the old line.
        session.keystrokeArrived()
        let endsLine = Self.endsLine(key, composing: composingAtLastRead)
        if endsLine { session.lineEnded() }
        // The line just changed, so the ghost at the old caret, a pass about the old prefix and a booked wake are all stale.
        withdraw()
        wake(endsLine ? .returnPressed : .keystroke)
    }

    /// Whether a key ends the line: a Return does, unless an input method was composing, when it confirms a conversion.
    nonisolated static func endsLine(_ key: Key, composing: Bool) -> Bool {
        key == .return && !composing
    }

    /// Advances prose fluency only for a text-producing key-down that is not autorepeat.
    nonisolated static func fluencyTimestamp(
        previous: Date, typing text: String?, isARepeat: Bool, at moment: Date
    ) -> Date {
        guard text != nil, !isARepeat else { return previous }
        return moment
    }

    /// Keeps the ghost up when the key typed its next letters, answering false for any other key, which withdraws it.
    private func typedThrough(_ text: String) -> Bool {
        guard panel.isShowing, !isInserting, let update = session.typedThrough(text) else { return false }
        // Whatever was being worked out was for the shorter line, and the turn woken below reads the new one.
        generating.cancel()
        cancelPendingWake()
        running?.cancel()
        interceptor.arm(update.armed)
        armedOffer = update.suggestion.accepting
        guard panel.advance(to: session.typed, showing: update.suggestion) else { return false }
        selectionGuard?.typedThrough(text)
        wake(.keystroke)
        return true
    }

    /// Another application came to the front, so whatever was being worked out for the last field is stale now.
    func applicationChanged(front: String?) {
        FocusedFieldReader.focusMayHaveMoved()
        withdraw()
        guard
            Self.shouldProcessActivityEvent(
                front: front,
                own: ownBundleIdentifier, preferences: preferences, at: Date())
        else {
            stopTicker()
            captureFeed.leaveApplication(at: Date())
            return
        }
        noteActivity()
        wake(.applicationChanged)
    }

    /// Books one turn for later, replacing any already booked, which is how a pause is answered the moment it is long enough.
    private func wake(_ reason: SuggestionReason, afterMilliseconds delay: Int) {
        guard activityIsAllowed() else {
            stopTicker()
            cancelPendingWake()
            return
        }
        cancelPendingWake()
        pendingWakeGeneration += 1
        let generation = pendingWakeGeneration
        pendingWake = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(max(delay, 1)))
            guard !Task.isCancelled, self?.pendingWakeGeneration == generation else { return }
            self?.pendingWake = nil
            self?.wake(reason)
        }
    }

    /// Cancels a booked wake and makes a task that already passed its sleep stale.
    private func cancelPendingWake() {
        pendingWakeGeneration += 1
        pendingWake?.cancel()
        pendingWake = nil
    }

    /// Runs one turn, or notes that another is wanted, so two never run at once and a stuck one never ends the loop.
    private func wake(_ reason: SuggestionReason) {
        // Secure keyboard entry can start inside the same app, where no activation rechecks it.
        checkSecureInput()
        guard !secureInput.isBlocking else { return }
        guard activityIsAllowed() else {
            stopTicker()
            cancelPendingWake()
            return
        }
        guard !wakeState.isStopped, !isDictating else { return }
        if reason == .keystroke || reason == .tick {
            let delay = Self.remainingFieldReadDebounce(sinceKeystroke: lastKeystroke, now: Date())
            if delay > 0 {
                wake(reason, afterMilliseconds: delay)
                return
            }
        }
        switch turns.begin(at: ContinuousClock.now) {
        case .busy:
            // A Return or a switch waiting its turn is never overwritten by the tick that follows it.
            _ = wakeState.queue(reason)
        case .stalled(let turn):
            Self.log.error(
                "\(SuggestionLog.stall(step: self.progress?.step, application: self.progress?.application, afterSeconds: TurnGate.stallSeconds), privacy: .public)"
            )
            generating.cancel()
            running?.cancel()
            start(turn, because: reason)
        case .free(let turn):
            start(turn, because: reason)
        }
    }

    /// Runs the turn the gate admitted and reports its end under the same number.
    private func start(_ turn: Int, because reason: SuggestionReason) {
        runningTurn = turn
        running = Task { [weak self] in
            await self?.turn(turn, because: reason)
            self?.finished(turn)
        }
    }

    /// Runs whatever arrived while the turn was in flight, unless the turn had already been left behind.
    private func finished(_ turn: Int) {
        if runningTurn == turn { runningTurn = nil }
        guard !wakeState.isStopped, turns.end(turn), let next = wakeState.takeAfterTurn() else {
            return
        }
        wake(next)
    }

    /// Notes the step a turn is about to wait on, ignored for a turn already left behind.
    private func entering(_ step: SuggestionTurnStep, turn number: Int) {
        guard progress?.turn == number else { return }
        progress?.step = step
    }

    // MARK: One turn

    /// The bundle identifier prefix every Uttrflow build carries, the release and the dev build alike.
    nonisolated static let uttrflowBundlePrefix = "com.uttrflow."

    /// Whether a turn may read the focused field at all: never in any Uttrflow build, nor where suggestions are off or paused.
    nonisolated static func shouldRead(
        front: String, own: String?, preferences: SuggestionPreferences, at moment: Date
    ) -> Bool {
        front != own && !front.hasPrefix(uttrflowBundlePrefix) && preferences.isEnabled(in: front, at: moment)
    }

    /// Disabled applications do not start the suggestion loop from their keystrokes or activation.
    nonisolated static func shouldProcessActivityEvent(
        front: String?, own: String?, preferences: SuggestionPreferences, at moment: Date
    ) -> Bool {
        guard let front else { return false }
        return shouldRead(front: front, own: own, preferences: preferences, at: moment)
    }

    func queueCaptureTyping(_ key: String?, from front: String?, at moment: Date) {
        guard
            Self.shouldProcessActivityEvent(
                front: front, own: ownBundleIdentifier, preferences: preferences, at: moment
            )
        else { return }
        captureFeed.queue(key)
    }

    /// Reads a redraw field only while suggestions remain enabled in the same application.
    nonisolated static func readForFreshDraw(
        front: String?, snapshot: FocusedFieldSnapshot, own: String?,
        preferences: SuggestionPreferences, read: @Sendable () async -> FocusedFieldSnapshot?
    ) async -> FocusedFieldSnapshot? {
        guard let front, front == snapshot.bundleIdentifier,
            shouldRead(front: front, own: own, preferences: preferences, at: Date())
        else { return nil }
        return await read()
    }

    /// Reads the field, asks the corpus and draws the answer, all off the keystroke path; a turn left behind touches nothing.
    func turn(_ number: Int, because reason: SuggestionReason) async {
        // Held rejection writes retry behind earlier corpus writes, so a slow store never delays the draw.
        if rejectedSuggestionRecorder.claimQueuedRetry() {
            let queued = acceptances.enqueue(
                { [rejectedSuggestionRecorder] in await rejectedSuggestionRecorder.retry() },
                estimatedBytes: rejectedSuggestionRecorder.queuedRetryReservationBytes())
            if !queued { rejectedSuggestionRecorder.cancelQueuedRetry() }
        }
        let front = frontmostBundleIdentifier() ?? "nil"
        progress = (number, .read, front)
        // Taken before the read, since a key pressed while a slow field is being read is one the read may have missed.
        let keystrokesSeen = session.keystrokes
        let shouldRead = Self.shouldRead(
            front: front, own: ownBundleIdentifier, preferences: preferences, at: Date())
        let readStarted = Date()
        let read = shouldRead ? await focusedFieldReader() : nil
        let readElapsed = Int(Date().timeIntervalSince(readStarted) * 1_000)
        Self.log.debug(
            "FIELD_READ front=\(SuggestionLog.application(front), privacy: .public) attempted=\(shouldRead) elapsedMs=\(readElapsed) read=\(read != nil)"
        )
        guard turns.isCurrent(number) else { return }
        composingAtLastRead = read?.markedText == .present
        Self.log.debug(
            "TURN front=\(SuggestionLog.application(front), privacy: .public) read=\(read != nil) lineChars=\(read?.currentLine.count ?? -1) value=\(read?.value != nil) units=\(read?.value?.utf16.count ?? -1) sel=\(read?.selection?.location ?? -1) caret=\(read?.caret != nil) role=\(read?.role ?? "-", privacy: .public) labelChars=\(read?.accessibilityDescription?.count ?? -1) identified=\(read?.identifier != nil) secure=\(read?.isSecure ?? false) placement=\(String(describing: read?.placement), privacy: .public)"
        )
        guard front != ownBundleIdentifier, let snapshot = read else {
            captureFeed.discard()
            draw(session.turn(in: nil, at: PredictionContext(typed: "")).step)
            return
        }
        let turnStartedAt = ContinuousClock.now
        let started = Date()
        guard preferences.isEnabled(in: snapshot.bundleIdentifier, at: started) else {
            captureFeed.discard()
            Self.log.debug(
                "OFF app=\(SuggestionLog.application(snapshot.bundleIdentifier), privacy: .public) not enabled in Suggestions"
            )
            draw(session.turn(in: nil, at: PredictionContext(typed: "")).step)
            return
        }

        let reading = reading(of: snapshot)
        // A new field or an emptied line is a fresh start: nothing drawn, no key held, nothing remembered of the last line.
        if reading.surface != session.surface {
            interceptor.arm([])
            panel.hide()
        }
        modelPass.freshStart(
            surfaceChanged: reading.surface != session.surface, lineIsEmpty: snapshot.currentLine.isEmpty)
        // A password field is refused here, before its value has been passed to anything at all.
        if snapshot.isSecure {
            await captureFeed.finishBeforeSecureRead(reading, at: started)
        } else {
            entering(.remember, turn: number)
            await captureFeed.remember(snapshot, as: reading, because: reason, at: started)
        }
        guard turns.isCurrent(number) else { return }
        captureFeed.lastReading = snapshot.isSecure ? nil : reading

        let turn = session.turn(
            in: reading.surface, at: context(of: snapshot, at: started),
            acceptKey: preferences.acceptKeys.key(
                for: AppContext(
                    applicationName: snapshot.applicationName,
                    bundleIdentifier: snapshot.bundleIdentifier,
                    documentName: snapshot.windowTitle)),
            isQuiet: preferences.isQuiet, sawKeystrokes: keystrokesSeen)
        if let rejected = turn.rejected, let surface = reading.surface {
            entering(.reject, turn: number)
            _ = acceptances.enqueue(
                { [rejectedSuggestionRecorder] in
                    await rejectedSuggestionRecorder.record(rejected, in: surface)
                }, estimatedBytes: AcceptanceQueue.estimatedBytes(for: [rejected], surface: surface))
        }

        switch turn.step {
        case .settled(let update):
            settle(update, in: snapshot)
        case .query(let query):
            entering(.corpus, turn: number)
            let candidates = await candidates(for: query)
            let ready = await generator?.isReady ?? false
            guard turns.isCurrent(number) else { return }
            panel.statusMessage =
                SuggestionEnergyStatus.shouldAnnouncePause(for: generator)
                ? "Suggestions are paused while Low Power Mode or thermal pressure is active."
                : nil
            Self.log.debug(
                "\(SuggestionLog.query(typed: query.typed, corpus: candidates.count, generatorReady: ready), privacy: .public)"
            )
            guard let update = await remembered(number, candidates, for: query, since: turnStartedAt),
                turns.isCurrent(number)
            else { return }
            // When nothing remembered can be drawn — nothing held, the line itself, or a line the gates refused — the model invents the suggestion instead.
            guard ModelPass.shouldAsk(after: update, hasGenerator: generator != nil, isReady: ready),
                let generator
            else {
                return settle(update, in: snapshot)
            }
            // The machine says first what the next word may be: anything, one of its values, or nothing here, which no pass can improve on.
            entering(.options, turn: number)
            let options = await verifier.options(for: query.typed, in: query.surface, now: .now)
            guard turns.isCurrent(number) else { return }
            switch options {
            case .none:
                Self.log.debug("\(SuggestionLog.optionsNone(typed: query.typed), privacy: .public)")
                modelPass.rememberEmpty(query, at: SuggestionMoment.place(of: snapshot))
                guard
                    let quiet = session.resolveGenerated(
                        [], for: query, elapsedMilliseconds: since(turnStartedAt),
                        whenEmpty: .notOnThisMachine, scores: [:])
                else { return }
                settle(quiet, in: snapshot)
            case .among(let values):
                Self.log.debug(
                    "\(SuggestionLog.optionsAmong(typed: query.typed, among: values.count), privacy: .public)"
                )
                await generate(
                    number, with: generator, for: query, in: snapshot, choosing: values, since: turnStartedAt)
            case .open:
                await generate(number, with: generator, for: query, in: snapshot, since: turnStartedAt)
            }
        }
    }

    /// Draws the update and, when it draws nothing, says why, so a silence is never logged without its reason.
    private func settle(_ update: SuggestionUpdate, in snapshot: FocusedFieldSnapshot) {
        if let silence = update.silence {
            Self.log.debug(
                "\(SuggestionLog.quiet(typed: snapshot.currentLine, reason: silence.rawValue, rejections: self.session.rejectionsHere, silencedHere: self.session.isSilencedHere, enabled: self.session.isEnabled), privacy: .public)"
            )
            // A prose pause is answered the moment it is long enough, rather than at whatever tick comes next.
            if silence == .writingFluently {
                let delay = Self.hesitationWake(sinceKeystroke: lastFluentKeystroke, now: Date())
                wake(.tick, afterMilliseconds: delay)
            }
        }
        panel.statusMessage = nil
        draw(update, in: snapshot)
    }

    /// What the corpus and the gates make of the line: the update they settle on, or nothing once the turn was left behind.
    private func remembered(
        _ number: Int, _ candidates: [Candidate], for query: SuggestionQuery,
        since started: ContinuousClock.Instant
    ) async -> SuggestionUpdate? {
        switch session.resolve(candidates, for: query, now: Date(), elapsedMilliseconds: since(started)) {
        case .settled(let update): return update
        case .verify(let request):
            entering(.verify, turn: number)
            return await verify(number, request, since: started)
        case nil: return nil
        }
    }

    /// Draws an answer that took a while against the field as it is now, so a scrolled or moved caret is followed and a changed line is not written over.
    private func drawFresh(
        _ update: SuggestionUpdate, for snapshot: FocusedFieldSnapshot, turn number: Int
    ) async {
        let keystrokesSeen = session.keystrokes
        // The session already holds this answer, so the key armed for the drawn one is let go until this one is drawn.
        if !Self.keepsClaimWhileReading(armed: armedOffer, next: update.suggestion) {
            stopWatchingSelection()
            interceptor.arm([])
            panel.hide()
            armedOffer = nil
        }
        entering(.redraw, turn: number)
        let front = frontmostBundleIdentifier()
        guard
            let fresh = await Self.readForFreshDraw(
                front: front, snapshot: snapshot, own: ownBundleIdentifier, preferences: preferences,
                read: focusedFieldReader),
            turns.isCurrent(number),
            ModelPass.isFresh(
                keystrokesBefore: keystrokesSeen, keystrokesNow: session.keystrokes,
                isCurrent: session.isCurrent,
                sameReading: reading(of: fresh) == reading(of: snapshot),
                sameLine: fresh.currentLine == snapshot.currentLine)
        else { return }
        draw(update, in: fresh)
    }

    /// Whether the key armed for the drawn line may stay armed while an answer offering `next` waits for its field read.
    nonisolated static func keepsClaimWhileReading(armed: String?, next: Suggestion) -> Bool {
        armed == next.accepting
    }

    /// Asks the model for a suggestion the corpus never held, from the field read live, held to the machine's values where it has them, and draws it.
    private func generate(
        _ number: Int, with generator: any CandidateGenerating, for query: SuggestionQuery,
        in snapshot: FocusedFieldSnapshot, choosing choices: [String] = [],
        since started: ContinuousClock.Instant
    ) async {
        let completions: [String]
        // Whether the model wrote lines and the machine denied every one, which is a silence with its own name.
        var invented = false
        var reused = false
        var reusedListed: Set<String> = []
        var reusedScores: [String: Double] = [:]
        let place = SuggestionMoment.place(of: snapshot)
        // A deletion, another line or changed text before it leaves the last answer describing a line that is gone.
        modelPass.follow(query, at: place)
        switch modelPass.plan(for: query, at: place) {
        case .reuse(let kept, let listed):
            // A kept line meets the machine again, since what it names may have changed since it was written.
            entering(.attest, turn: number)
            completions = await attested(kept, for: query)
            guard turns.isCurrent(number) else { return }
            reusedListed = listed
            reusedScores = modelPass.scores(for: completions)
            reused = true
        case .skip:
            return
        case .ask:
            // Measured from the key, not from here, so a pause already long enough waits no second time.
            let quiet = Self.remainingDebounce(sinceKeystroke: lastKeystroke, now: Date())
            let pass = Task { [generator, store, contextCache] in
                // A short quiet first, so a burst of keystrokes costs one pass for its last prefix rather than one per key.
                try? await Task.sleep(for: quiet)
                guard !Task.isCancelled else { return [String]() }
                // The context is read only once a pass is certain, so a cancelled burst never pays for it.
                let situation = await Self.situation(
                    of: snapshot, for: query, store: store, cache: contextCache, turn: number
                ).choosing(choices)
                return try await generator.completions(for: query.typed, in: situation)
            }
            generating.store(pass, for: number)
            entering(.generate, turn: number)
            let answer = await pass.result
            generating.finish(turn: number)
            // A pass the next keystroke cancelled, or a turn left behind, answers a line that is gone: nothing is drawn or kept.
            guard !pass.isCancelled, turns.isCurrent(number) else { return }
            switch answer {
            case .failure(let error):
                // A failed pass is remembered like an empty one, so a tick never re-runs the failure, but it is never logged as one.
                modelPass.rememberEmpty(query, at: place)
                Self.log.error(
                    "\(SuggestionLog.generateFailed(typed: query.typed, error: error), privacy: .public)")
                return
            case .success(let lines):
                entering(.attest, turn: number)
                let standing = await attested(lines, for: query)
                guard turns.isCurrent(number) else { return }
                invented = !lines.isEmpty && standing.isEmpty
                completions = standing
            }
        }
        Self.log.debug(
            "\(SuggestionLog.generate(application: snapshot.applicationName, typed: query.typed, got: completions.count, elapsedMilliseconds: self.since(started), firstCompletion: completions.first), privacy: .public)"
        )
        // Every generated line carries the score its own pass gave it, so a low or missing score leaves the turn quiet.
        entering(.score, turn: number)
        let scores: [String: Double]
        if reused {
            scores = reusedScores
        } else {
            scores = await verifier.scoreCompletions(completions)
            modelPass.remember(completions, for: query, at: place, scores: scores)
        }
        guard turns.isCurrent(number) else { return }
        guard
            let update = session.resolveGenerated(
                completions, for: query, elapsedMilliseconds: since(started),
                whenEmpty: invented ? .notOnThisMachine : .nothingOffered, scores: scores,
                listed: reusedListed)
        else { return }
        // A silence has nothing to place, so it is settled and logged against the field it read.
        guard update.silence == nil else { return settle(update, in: snapshot) }
        // A kept answer is ready as the turn's own read is taken, and its alternatives were already sought when it was written.
        guard !reused else { return draw(update, in: snapshot) }
        await drawFresh(update, for: snapshot, turn: number)
        // With the one line on screen, the others are fetched behind it, so Down has a list and the person never waited for it.
        guard completions.count == 1, let leader = completions.first, turns.isCurrent(number) else { return }
        // Quiet keeps the one-line ghost and never spends a pass on alternatives.
        guard !preferences.isQuiet else { return }
        // Where the machine gave the values, the other values are the alternatives, and no pass is spent on them.
        if case .values(let listed) = ModelPass.alternativesSource(
            typed: query.typed, choices: choices, leader: leader)
        {
            // The machine's values still pass the gate, since a listed name can be destructive or stale by now.
            entering(.attest, turn: number)
            let others = await attested(listed, for: query)
            // A value the machine listed exists, so it needs no score to stand among the alternatives.
            guard turns.isCurrent(number), !others.isEmpty,
                let expanded = session.expandGenerated(others, for: query, scores: nil)
            else { return }
            modelPass.remember(
                [leader] + others, for: query, at: place, listed: Set(others), scores: scores)
            return await drawFresh(expanded, for: snapshot, turn: number)
        }
        let more = Task { [generator, store, contextCache] in
            let situation = await Self.situation(
                of: snapshot, for: query, store: store, cache: contextCache, turn: number)
            return try await generator.alternatives(for: query.typed, in: situation, excluding: leader)
        }
        generating.store(more, for: number)
        entering(.alternatives, turn: number)
        let followUp = await more.result
        generating.finish(turn: number)
        guard !more.isCancelled, turns.isCurrent(number) else { return }
        guard case .success(let others) = followUp else {
            // The one line stays on screen; only the list behind it is missing, and the log says why.
            if case .failure(let error) = followUp {
                Self.log.error(
                    "\(SuggestionLog.alternativesFailed(typed: query.typed, error: error), privacy: .public)")
            }
            return
        }
        entering(.attest, turn: number)
        let standing = await attested(others, for: query)
        entering(.score, turn: number)
        let standingScores = await verifier.scoreCompletions(standing)
        guard turns.isCurrent(number), !standing.isEmpty,
            let expanded = session.expandGenerated(standing, for: query, scores: standingScores)
        else { return }
        modelPass.remember(
            [leader] + standing, for: query, at: place,
            scores: scores.merging(standingScores) { _, new in new })
        Self.log.debug(
            "\(SuggestionLog.alternatives(typed: query.typed, got: others.count, elapsedMilliseconds: self.since(started)), privacy: .public)"
        )
        await drawFresh(expanded, for: snapshot, turn: number)
    }

    /// The model's lines the machine lets stand, with how many it denied counted in the log; a program, path or branch this Mac does not have is never drawn.
    private func attested(_ lines: [String], for query: SuggestionQuery) async -> [String] {
        let standing = await verifier.standing(lines, after: query.typed, in: query.surface, now: .now)
        if standing.count < lines.count {
            Self.log.debug(
                "\(SuggestionLog.attest(typed: query.typed, offered: lines.count, standing: standing.count), privacy: .public)"
            )
        }
        return standing
    }

    /// Milliseconds until the prose pause after the latest keystroke is long enough, counted from now rather than from the turn's start.
    nonisolated static func hesitationWake(sinceKeystroke keystroke: Date, now: Date) -> Int {
        let passed = max(0, Int(now.timeIntervalSince(keystroke) * 1000))
        return max(0, Quieting.proseHesitationInMilliseconds - passed) + 20
    }

    /// What is left of the debounce for a key pressed at `keystroke`, which is nothing once the pause is long enough.
    nonisolated static func remainingDebounce(sinceKeystroke keystroke: Date, now: Date) -> Duration {
        let passed = max(0, now.timeIntervalSince(keystroke) * 1000)
        return .milliseconds(max(0, Double(Self.generationDebounceInMilliseconds) - passed))
    }

    /// Milliseconds left before typing has paused long enough to read the field.
    nonisolated static func remainingFieldReadDebounce(sinceKeystroke keystroke: Date, now: Date) -> Int {
        let passed = max(0, now.timeIntervalSince(keystroke) * 1000)
        let remaining = Double(Self.fieldReadDebounceInMilliseconds) - passed
        return remaining <= 0.001 ? 0 : Int(ceil(remaining - 0.001))
    }

    /// Whether the window around this field is walked, which a terminal's is not since its value already holds the scrollback.
    nonisolated static func walksSurroundings(of snapshot: FocusedFieldSnapshot) -> Bool {
        !TerminalApplications.contains(snapshot.bundleIdentifier)
    }

    /// The text around the field, or nothing where the window is not walked.
    private static func surroundings(
        of snapshot: FocusedFieldSnapshot, cache: SuggestionContextCache
    ) async -> Surroundings? {
        guard walksSurroundings(of: snapshot) else { return nil }
        return await cache.surroundings(for: SuggestionMoment.windowKey(of: snapshot)) {
            await FocusedFieldReader.surroundings()
        }
    }

    /// Reads what is on screen and what this person wrote here, then maps them with ``SuggestionMoment``.
    private static func situation(
        of snapshot: FocusedFieldSnapshot, for query: SuggestionQuery, store: PredictStore,
        cache: SuggestionContextCache, turn: Int
    ) async -> GenerationSituation {
        // The alternatives pass asks about the same line in the same turn, so it is told what the first pass was.
        if let built = await cache.situation(forTurn: turn) { return built }
        // Neither read needs the other, so the walk and the corpus query run side by side.
        async let walk = surroundings(of: snapshot, cache: cache)
        async let remembered =
            (try? await store.recent(in: query.surface, limit: SuggestionMoment.recentLinesShown)) ?? []
        let around = await walk
        let recent = SuggestionMoment.recentLines(await remembered, typing: query.typed)
        let situation = SuggestionMoment.situation(of: snapshot, surroundings: around, recentLines: recent)
        // Lengths only, since what is on screen and what the person wrote are theirs and stay out of the log.
        Self.log.debug(
            "CONTEXT title=\(around?.windowTitle?.count ?? 0) around=\(around?.text?.count ?? 0) recent=\(recent.count) preceding=\(situation.preceding?.count ?? 0)"
        )
        await cache.remember(situation, forTurn: turn)
        return situation
    }

    /// Puts the head of the ranking through the gates and draws whatever survives them.
    private func verify(
        _ number: Int, _ request: VerificationRequest, since started: ContinuousClock.Instant
    ) async -> SuggestionUpdate? {
        let allowed = await verifier.verified(
            request.candidates, in: request.surface, typed: request.typed, now: .now)
        guard turns.isCurrent(number) else { return nil }
        Self.log.debug(
            "\(SuggestionLog.verify(typed: request.typed, offered: request.candidates.count, allowed: allowed.count, elapsedMilliseconds: self.since(started), firstCompletion: allowed.first?.text), privacy: .public)"
        )
        // The gates answer within a moment, so the field read at the turn's start still stands for whatever is drawn.
        return session.resolve(allowed, for: request, now: Date(), elapsedMilliseconds: since(started))
    }

    /// How long this turn has taken, which is what decides whether its answer is still worth drawing.
    nonisolated static func elapsedMilliseconds(
        since started: ContinuousClock.Instant, now: ContinuousClock.Instant
    ) -> Int {
        let elapsed = started.duration(to: now).components
        let milliseconds = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
        return Int(max(0, milliseconds))
    }

    private func since(_ started: ContinuousClock.Instant) -> Int {
        Self.elapsedMilliseconds(since: started, now: .now)
    }

    /// What the corpus remembers, or failing that what this machine holds at `now`; the machine never outranks the person's own history.
    func candidates(
        for query: SuggestionQuery, at now: ContinuousClock.Instant = .now
    ) async -> [Candidate] {
        let candidates = await CandidateSources.candidates(
            from: store, environment: environment, for: query.surface, matching: query.typed, now: now)
        return candidates.filter {
            !rejectedSuggestionRecorder.suppresses($0.text, in: query.surface)
        }
    }

    // MARK: Drawing

    /// Draws whatever a turn with no field behind it settled on, which is always nothing.
    private func draw(_ step: SuggestionStep) {
        guard !wakeState.isStopped, !isPointerGestureActive, !nativeMenuIsOpen,
            case .settled(let update) = step
        else { return }
        panel.statusMessage = nil
        stopWatchingSelection()
        interceptor.arm(update.armed)
        armedOffer = update.suggestion.accepting
        panel.hide()
        captureFeed.lastReading = nil
    }

    /// Arms the tap first and draws second, so no key is claimed that nothing is offering.
    func draw(_ update: SuggestionUpdate, in snapshot: FocusedFieldSnapshot?) {
        checkSecureInput()
        // A stopped loop, secure keyboard entry, a held pointer gesture, or a stale read draws nothing and claims no key.
        guard !wakeState.isStopped, !isPointerGestureActive, !nativeMenuIsOpen, !secureInput.isBlocking,
            session.isCurrent
        else {
            stopWatchingSelection()
            interceptor.arm([])
            panel.hide()
            return
        }
        if panel.statusMessage != nil {
            panel.statusMessage = nil
        }
        interceptor.arm(update.armed)
        armedOffer = update.suggestion.accepting
        // Nothing is drawn off the caret's line, and what is not drawn claims no key.
        guard let snapshot, snapshot.placement == .inlineGhost,
            let caret = Self.caret(for: update.suggestion, in: snapshot)
        else {
            stopWatchingSelection()
            interceptor.arm([])
            armedOffer = nil
            panel.hide()
            return
        }
        closingPunctuationAfterCaret = snapshot.closingPunctuationAfterCaret
        let visibleSuggestion = update.suggestion.trimmed(
            after: session.typed, matching: closingPunctuationAfterCaret)
        let shown = panel.show(
            visibleSuggestion, typed: session.typed, placement: .inlineGhost,
            direction: snapshot.writingDirection == .rightToLeft ? .rightToLeft : .leftToRight,
            caret: caret, window: snapshot.window, field: snapshot.ghostField,
            fieldPointSize: snapshot.pointSize,
            selection: session.selection,
            acceptKey: preferences.acceptKeys.key(
                for: AppContext(
                    applicationName: snapshot.applicationName,
                    bundleIdentifier: snapshot.bundleIdentifier,
                    documentName: snapshot.windowTitle)),
            fontFamily: snapshot.fontFamily, isBold: snapshot.isBold, isItalic: snapshot.isItalic,
            textColor: snapshot.textColor)
        // An offer the panel could not show whole claims no key, so Tab never inserts what was not drawn.
        guard shown else {
            stopWatchingSelection()
            interceptor.arm([])
            armedOffer = nil
            return
        }
        armSelectionMonitor(
            for: update.suggestion, at: snapshot.selection, identity: snapshot.focusedFieldIdentity)
        watchScrolls()
    }

    /// The caret a ghost for `suggestion` is drawn at, or nil when the field offers no inline place for one.
    nonisolated static func caret(for suggestion: Suggestion, in snapshot: FocusedFieldSnapshot) -> CGRect? {
        guard suggestion != .silent, snapshot.placement == .inlineGhost else { return nil }
        return snapshot.caret
    }

    /// Draws what a move or a dismissal left where the ghost already stands, since no field was read for it and typing may have moved it.
    private func redraw(_ update: SuggestionUpdate) {
        guard !wakeState.isStopped, !isPointerGestureActive, !nativeMenuIsOpen, session.isCurrent else {
            stopWatchingSelection()
            interceptor.arm([])
            panel.hide()
            return
        }
        if panel.statusMessage != nil { panel.statusMessage = nil }
        interceptor.arm(update.armed)
        armedOffer = update.suggestion.accepting
        let visibleSuggestion = update.suggestion.trimmed(
            after: session.typed, matching: closingPunctuationAfterCaret)
        guard panel.redraw(visibleSuggestion, typed: session.typed, selection: session.selection) else {
            stopWatchingSelection()
            interceptor.arm([])
            armedOffer = nil
            return
        }
    }

    // MARK: Accepting

    /// Every key the tap took, decided in the session and carried out here.
    private func watchSwallowedKeys() {
        swallowed?.cancel()
        swallowed = Task { [weak self, interceptor] in
            for await event in interceptor.events {
                guard let self else { return }
                await handle(event)
            }
        }
    }

    /// One key the tap took, which is either the tap giving up or something the session decides.
    private func handle(_ event: InterceptedEvent) async {
        switch event {
        case .stopped(let failure):
            Self.log.error("the tap stopped: \(String(describing: failure), privacy: .public)")
            restTap()
        case .swallowed(let stroke):
            let typed = session.typed
            let reading = captureFeed.lastReading
            let action = session.route(stroke)
            Self.log.debug(
                "SWALLOWED key=\(String(describing: stroke.key), privacy: .public) modifiers=\(stroke.modifiers.rawValue) decision=\(Self.name(of: action), privacy: .public)"
            )
            switch action {
            case .accept(let text):
                stopWatchingSelection()
                panel.hide()
                interceptor.arm([])
                generating.cancel()
                // Held across the insert so the keys it posts are ignored on both the tap and the monitor.
                isInserting = true
                let returnedKey = await Self.acceptKeyToReturnIfTakeFails(stroke) {
                    await take(
                        text, after: typed, in: reading,
                        closingPunctuation: closingPunctuationAfterCaret)
                } requestFreshRead: {
                    wake(.tick)
                } completed: { outcome in
                    session.completeAcceptance(outcome)
                }
                isInserting = false
                // A field that is no longer the drawn line gets its key back, so Tab still does what Tab does there.
                if let returnedKey { KeyStrokeReturn.post(returnedKey) }
                noteActivity()
            // The field-value observer wakes after the destination exposes its insertion; the activity ticker is the fallback.
            case .redraw(let update):
                redraw(update)
            case .giveBack(let refused):
                KeyStrokeReturn.post(refused)
            }
            // The keys pressed since this one reach the application only now, after anything it inserted.
            interceptor.releaseHeldKeys()
            // ⌥⎋ turns the feature off everywhere; persist it so the switch agrees and a later enable rebuilds this.
            if !session.isEnabled {
                if let onTurnedOffEverywhere { onTurnedOffEverywhere() } else { stop() }
            }
        }
    }

    /// How long the tap rests after macOS disabled it twice, past the window in which disables count against it.
    private static let tapRestSeconds = 90

    /// Rests the tap and starts it again, since a disable is usually the system's doing and the feature need not die of it.
    private func restTap() {
        onTapRestChanged?(nil)
        interceptor.arm([])
        interceptor.stop()
        panel.hide()
        tapRest.schedule(
            after: .seconds(Self.tapRestSeconds),
            shouldRestart: { [weak self] in
                guard let self else { return false }
                return !wakeState.isStopped && !secureInput.isBlocking
            },
            willRestart: { [weak self] in self?.onTapRestRestarting?() }
        ) { [weak self] in
            guard let self, !wakeState.isStopped, !secureInput.isBlocking else { return }
            do {
                try interceptor.start()
                Self.log.error("the tap is back after resting \(Self.tapRestSeconds)s")
                onTapRestChanged?(.success(()))
            } catch {
                Self.log.error("the tap could not restart: \(SuggestionLog.failure(error), privacy: .public)")
                onTapRestChanged?(.failure(error))
            }
        }
    }

    /// The one word the log carries for a routed keystroke.
    private static func name(of action: SuggestionAction) -> String {
        switch action {
        case .accept: "accept"
        case .redraw: "redraw"
        case .giveBack: "giveBack"
        }
    }

    /// Returns the accept stroke only when the field is known to be unchanged.
    static func acceptKeyToReturnIfTakeFails(
        _ stroke: UttrflowCore.KeyStroke, taking: () async -> UttrflowPredict.AcceptanceOutcome,
        requestFreshRead: () -> Void,
        completed: (UttrflowPredict.AcceptanceOutcome) -> Void = { _ in }
    ) async -> UttrflowCore.KeyStroke? {
        let outcome = await taking()
        completed(outcome)
        if outcome == .mayHaveWritten { requestFreshRead() }
        return outcome == .refused ? stroke : nil
    }

    /// Whether an insertion error proves that no suggestion text reached the field.
    static func acceptanceOutcome(for error: TextInsertionError) -> UttrflowPredict.AcceptanceOutcome {
        switch error {
        case .noFocusedTextField, .accessibilityDenied, .insertionRejected, .insertionNeedsCopy,
            .insertionTargetChanged, .insertionFieldClosed:
            .refused
        case .clipboardUnavailable, .clipboardChanged, .insertionTimedOut, .insertionCancelled,
            .insertionUnconfirmed, .insertionInterrupted:
            .mayHaveWritten
        }
    }

    /// Puts the tail into the field and queues the taken line for capture, reporting uncertain writes.
    private func take(
        _ text: String, after typed: String, in reading: FieldReading?, closingPunctuation: String
    ) async -> UttrflowPredict.AcceptanceOutcome {
        // What the gates left is a whole line, so taking it may replace characters as well as add.
        guard let windowNumber = reading?.surface?.windowNumber else {
            Self.log.error("the drawn field has no identifiable window; giving the key back")
            return .refused
        }
        var via = "nothing"
        let accepted = Suggestion.certain(text).trimmed(
            after: typed, matching: closingPunctuation)
        do throws(TextInsertionError) {
            via =
                try await acceptor.accept(
                    accepted, after: typed, expectedWindowNumber: windowNumber)?.rawValue ?? via
        } catch {
            // A refusal for lost trust withdraws suggestions and tells the menu bar, as the next activation would.
            if error == .accessibilityDenied { activationMonitor?.recheckForLoss() }
            let outcome = Self.acceptanceOutcome(for: error)
            if outcome == .refused {
                Self.log.error(
                    "\(SuggestionLog.landedNowhere(error, typed: typed), privacy: .public)")
            } else {
                Self.log.error(
                    "\(SuggestionLog.deliveryUnconfirmed(error, typed: typed), privacy: .public)")
            }
            return outcome
        }
        Self.log.debug(
            "\(SuggestionLog.accept(text: text, typed: typed, via: via), privacy: .public)"
        )
        guard let reading else { return .inserted }
        let moment = Date()
        let log = Self.log
        let bytes = AcceptanceQueue.estimatedBytes(
            for: [
                text, typed, reading.bundleIdentifier, reading.role, reading.subrole, reading.identifier,
                reading.placeholder, reading.accessibilityDescription, reading.document, reading.windowTitle,
                reading.applicationName,
            ], surface: reading.surface)
        _ = acceptances.enqueue(
            { [capture] in
                do {
                    _ = try await capture.accepted(text, over: typed, in: reading, at: moment)
                } catch {
                    // The session holds the acceptance and retries it before the next event.
                    log.error("An accepted suggestion's corpus write failed and is held for a retry")
                }
            }, estimatedBytes: bytes)
        return .inserted
    }

    // MARK: Consent

    /// What the field publishes about itself, in the shape the corpus keys entries by.
    private func reading(of snapshot: FocusedFieldSnapshot) -> FieldReading {
        SuggestionMoment.reading(of: snapshot)
    }

    /// Everything about this moment that can silence a suggestion.
    private func context(of snapshot: FocusedFieldSnapshot, at moment: Date) -> PredictionContext {
        SuggestionMoment.context(
            of: snapshot,
            millisecondsSinceKeystroke: Self.elapsedMilliseconds(since: lastFluentKeystroke, at: moment))
    }
}
