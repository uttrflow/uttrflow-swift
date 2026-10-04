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

/// Why the loop is running this turn, which decides what capture is told about it.
private enum SuggestionReason {
    /// A key was pressed in another application.
    case keystroke
    /// Return was pressed, which is the user saying the value is finished.
    case returnPressed
    /// The application in front changed.
    case applicationChanged
    /// Time passed, which is the only way a pause can be noticed.
    case tick

    /// What must not be lost to a later wake: a Return commits a line, a switch changes the field, a tick changes nothing.
    var urgency: Int {
        switch self {
        case .returnPressed: 3
        case .applicationChanged: 2
        case .keystroke: 1
        case .tick: 0
        }
    }

    /// The event capture is handed for this turn, carrying the line rather than the whole field.
    func event(holding value: String, at moment: Date) -> CaptureEvent {
        switch self {
        case .keystroke, .applicationChanged: .keystroke(value, at: moment)
        case .returnPressed: .returnPressed(at: moment)
        case .tick: .tick(at: moment)
        }
    }
}

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

    private let store: PredictStore
    private let rejectedSuggestionRecorder: RejectedSuggestionRecorder
    let capture: CaptureSession
    private let panel = SuggestionPanelController.shared
    private let interceptor = KeyInterceptor()
    private let secureInput = SecureInputWatch()
    /// Whether secure keyboard entry is holding suggestions off, as this coordinator last saw it.
    var isSecureInputBlocking: Bool { secureInput.isBlocking }
    private let acceptor: SuggestionAcceptor
    private let focusedFieldValueObserver: any FocusedFieldValueObserving
    /// Keeps background typing work responsive for the coordinator's lifetime.
    private let processActivity: any SuggestionProcessActivityManaging
    /// What the user has decided on the Suggestions screen, which the app hands over as it changes.
    private var preferences: SuggestionPreferences
    /// Whether a native menu currently owns keyboard gestures in the focused application.
    private var nativeMenuIsOpen = false
    /// What exists on this machine right now, which the corpus cannot know. See `Docs/predict.md`.
    private let environment: EnvironmentSource
    /// The gates that decide whether a candidate is right, which is not what the ranking measures.
    private let verifier: Verifier
    /// The model that invents a suggestion when the corpus has none, absent until the app hands one over.
    private let generator: (any CandidateGenerating)?
    /// Reads only focus identity and selection while a completion is armed.
    private let focusedSelectionReader: @Sendable () async -> FocusedFieldSelection?
    /// What the model last answered or had nothing for, which decides whether it is asked again.
    private var modelPass = ModelPass()
    /// The model pass in flight, cancelled by the next keystroke so a burst never queues one pass per key.
    private var generating: Task<[String], any Error>?
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

    private var session = SuggestionSession()
    private var monitors: [Any] = []
    /// The scroll monitor, present only while a ghost is drawn, since a scroll matters only then.
    private var scrollMonitor: Any?
    private var secureInputObserver: (any NSObjectProtocol)?
    private var activityIsWatched = false
    /// Polls only the focused selection while a ghost can still be accepted.
    private var selectionTimer: Timer?
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
    /// Whether field observation is active or kept alive by a visible ghost.
    private var ticking = SuggestionTicking()
    private var swallowed: Task<Void, Never>?
    private var lastReading: FieldReading?
    /// Closing punctuation already present after the caret of the current offer.
    private var closingPunctuationAfterCaret = ""
    /// The line capture was last handed as a keystroke, and the field it was in, so a Return can catch up what it displaced.
    private var handed: (line: String, reading: FieldReading)?
    /// The line the accept key takes as last armed by a draw, so a later answer never inherits that claim.
    private(set) var armedOffer: String?
    var isSelectionPolling: Bool { selectionTimer != nil }
    var isTickerScheduled: Bool { ticker != nil }
    private var lastKeystroke = Date.distantPast
    /// The last observed key-down, used to distinguish typing from edits made without a key.
    private var lastObservedKeyDown = Date.distantPast
    /// One turn at a time, with a turn that never returns left behind so the loop cannot die with it.
    private var turns = TurnGate()
    /// The step the newest turn is waiting on and the bundle identifier it read, so a stall names where it stuck.
    private var progress: (turn: Int, step: SuggestionTurnStep, application: String)?
    /// What this turn has already been told about the moment, so one line costs one walk.
    private let contextCache = SuggestionContextCache()
    /// True while an accepted completion is being inserted, so the keys it posts wake no further turn.
    private var isInserting = false
    /// True once the loop is stopped, so a turn still finishing draws nothing into the shared panel.
    private var isStopped = false
    /// Set while a dictation is under way, when no turn may start.
    private var isDictating = DictationInProgress.shared.isDictating
    /// Whether the last field read reported marked text, so a Return next confirms a conversion rather than ending the line.
    private var composingAtLastRead = false
    /// The accepted lines still being written to the corpus, which a held key never waits on.
    let acceptances = AcceptanceQueue()
    /// Set when a paste or a dictation put text in the field that capture has not yet been told was never typed.
    private var insertionPending = false
    /// Printable keyboard input not yet checked against the next accessibility read.
    private var pendingCaptureTyping: [String?] = []
    private var again: SuggestionReason?
    private let ownBundleIdentifier = Bundle.main.bundleIdentifier
    /// Called when the user turns the feature off everywhere, so the choice is persisted and can be undone.
    var onTurnedOffEverywhere: (() -> Void)?
    /// Tells the menu bar why suggestion input is paused.
    var onSecureInputBlockingChanged: ((Bool) -> Void)?
    var onTapRestChanged: ((Result<Void, any Error>?) -> Void)?
    var onSecureInputChanged: ((Bool) -> Void)?

    /// Opens the corpus, or reports why it could not; the scorer, when given, is the model that validates.
    init(
        container: URL, preferences: SuggestionPreferences,
        scoring: (any CandidateScoring)? = nil, generating: (any CandidateGenerating)? = nil,
        encryptedStore: EncryptedStore? = nil,
        environmentIndex: EnvironmentIndex? = nil,
        focusedFieldValueObserver: (any FocusedFieldValueObserving)? = nil,
        processActivity: any SuggestionProcessActivityManaging = ProcessSuggestionActivity(),
        focusedSelectionReader: @escaping @Sendable () async -> FocusedFieldSelection? = {
            await FocusedFieldReader.focusedSelection()
        }
    ) throws(PredictStoreError) {
        self.preferences = preferences
        self.processActivity = processActivity
        self.generator = generating
        self.focusedSelectionReader = focusedSelectionReader
        self.focusedFieldValueObserver = focusedFieldValueObserver ?? FocusedFieldValueObserver()
        let store = try PredictStore(
            path: PredictStore.defaultFile(in: container).path(percentEncoded: false),
            encryptedStore: encryptedStore)
        self.store = store
        rejectedSuggestionRecorder = RejectedSuggestionRecorder(store: store)
        // Lines learned before the credential rules last widened are removed once, off the typing path.
        Task.detached(priority: .utility) { _ = try? await CaptureGate.sweepSecrets(from: store) }
        // One index behind both, so asking the machine for a completion also warms what attests it.
        let index = environmentIndex ?? EnvironmentIndex(reader: SystemEnvironmentReader())
        environment = EnvironmentSource(index: index)
        // The model, when the app hands one over, is what turns a habit into a validated suggestion.
        verifier = Verifier(index: index, scoring: scoring, supersession: store)
        capture = CaptureSession(
            sink: store,
            preferencesFile: CapturePreferencesFile(
                path: CapturePreferencesFile.defaultFile(in: container).path(percentEncoded: false)),
            // A line that was never sent was not a value: a shell and a chat composer learn on Return alone.
            policy: .whereReturnSends)
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
        if Self.disablesSuggestions(
            in: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            before: before, after: preferences, at: moment)
        {
            withdraw()
        }
        // One switch, two stores: what may be suggested in is what may be learned from. See `Docs/predict.md`.
        Task { [capture] in
            for application in preferences.turnedOff.subtracting(before.turnedOff) {
                try? await capture.record(.declined, for: application)
            }
            for application in preferences.turnedOn.subtracting(before.turnedOn) {
                try? await capture.record(.allowed, for: application)
            }
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

    /// Forgets what one application taught, on disk and in every copy this loop holds.
    func forgetSuggestions(from bundleIdentifier: String) async throws {
        await capture.forgetLearned(from: bundleIdentifier)
        let store = self.store
        try await forgetWhatThisLoopRemembers(clearingCorpus: {
            try await store.forget(bundleIdentifier: bundleIdentifier)
        })
    }

    /// Forgets every line and answer, on disk and in every copy this loop holds.
    func forgetEverySuggestion() async throws {
        try await capture.forgetEverythingLearned()
        let store = self.store
        try await forgetWhatThisLoopRemembers(clearingCorpus: {
            try await store.forgetEverything()
        })
    }

    /// Drops the verdicts and model answers this loop keeps, which may name a forgotten line.
    private func forgetWhatThisLoopRemembers(
        clearingCorpus: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await verifier.forgetEverything(then: clearingCorpus)
        modelPass.freshStart(surfaceChanged: true, lineIsEmpty: true)
    }

    /// Arms the tap and starts watching, or says why it cannot.
    @discardableResult
    func start() -> Result<Void, any Error> {
        processActivity.begin()
        isStopped = false
        tapRest.cancel()
        secureInputObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.checkSecureInput()
                if !self.secureInput.isBlocking {
                    self.focusedFieldValueObserver.refresh()
                    self.applicationChanged()
                }
            }
        }
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
            withdraw()
            focusedFieldValueObserver.stop()
            interceptor.stop()
            onSecureInputBlockingChanged?(true)
            panel.announce(SecureInputWatch.suggestionNotice)
        } else {
            onSecureInputChanged?(false)
            onSecureInputBlockingChanged?(false)
            switch startInterceptor() {
            case .success: onTapRestChanged?(.success(()))
            case .failure(let error): onTapRestChanged?(.failure(error))
            }
        }
    }

    /// Takes the surface away, disarms the tap and stops watching.
    func stop() {
        processActivity.end()
        isStopped = true
        nativeMenuIsOpen = false
        onSecureInputBlockingChanged?(false)
        tapRest.cancel()
        session.invalidate()
        interceptor.arm([])
        interceptor.stop()
        panel.hide()
        swallowed?.cancel()
        swallowed = nil
        generating?.cancel()
        cancelPendingWake()
        running?.cancel()
        ticker?.invalidate()
        ticker = nil
        ticking = SuggestionTicking()
        isPointerGestureActive = false
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        stopWatchingScrolls()
        if let secureInputObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(secureInputObserver)
        }
        secureInputObserver = nil
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
            // A paste, the person's or this app's own, puts words in the line that were never typed.
            MainActor.assumeIsolated {
                self?.lastObservedKeyDown = observedAt
                if pastes { self?.insertionPending = true }
            }
            // A key this app inserted must not wake another turn, or the feature types on its own.
            if let cgEvent = event.cgEvent, SyntheticEvent.isOurs(cgEvent) { return }
            let text = Self.typedText(characters: event.characters, modifiers: event.modifierFlags)
            if !pastes, let self {
                MainActor.assumeIsolated {
                    if let text {
                        self.pendingCaptureTyping.append(text)
                    } else if Key(keyCode: event.keyCode) != .return {
                        self.pendingCaptureTyping.append(nil)
                    }
                }
            }
            if Self.mayMoveFocus(keyCode: event.keyCode, modifiers: event.modifierFlags) {
                FocusedFieldReader.focusMayHaveMoved()
            }
            MainActor.assumeIsolated { self?.keyPressed(Key(keyCode: event.keyCode), typing: text) }
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
                self?.focusedFieldValueObserver.refresh()
                self?.noteActivity()
                self?.withdraw()
                if delay > 0 {
                    self?.wake(.tick, afterMilliseconds: delay)
                } else {
                    self?.wake(.tick)
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
                self?.applicationChanged()
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
            onValueChanged: { [weak self] in self?.accessibilityValueChanged() },
            onNativeMenuVisibilityChanged: { [weak self] isOpen in
                guard let self else { return }
                nativeMenuIsOpen = isOpen
                interceptor.setNativeMenuIsOpen(isOpen)
                if isOpen {
                    withdraw()
                } else if !isStopped, !secureInput.isBlocking {
                    wake(.tick)
                }
            })
    }

    /// Withdraws an offer when the focused field changes without a corresponding key event.
    private func accessibilityValueChanged() {
        guard !isStopped, !isInserting else { return }
        let moment = Date()
        if Self.isUnkeyedAccessibilityChange(lastKeyDown: lastObservedKeyDown, at: moment) {
            insertionPending = true
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
        guard moment.timeIntervalSince(lastKeystroke) * 1000 >= Double(fieldReadDebounceInMilliseconds) else {
            return .ignore
        }
        return .withdrawAndWake
    }

    /// Whether a value change arrived without a nearby key-down to explain it.
    nonisolated static func isUnkeyedAccessibilityChange(lastKeyDown: Date, at moment: Date) -> Bool {
        moment.timeIntervalSince(lastKeyDown) * 1000 >= Double(accessibilityKeyWindowInMilliseconds)
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
            insertionPending = true
            wake(.tick)
            return
        }
        again = nil
        turns.abandon()
        withdraw()
    }

    /// Takes the ghost and the keys it claims away, and voids every answer in flight, because the caret may have moved under it.
    private func withdraw() {
        stopWatchingSelection()
        armedOffer = nil
        session.invalidate()
        generating?.cancel()
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

    /// Checks the caret every 200 ms only while a drawn offer can be accepted.
    func armSelectionMonitor(for suggestion: Suggestion, at range: NSRange?) {
        armedOffer = suggestion.accepting
        guard armedOffer != nil else { return stopWatchingSelection() }
        stopWatchingSelection()
        selectionGuard = ArmedSelectionGuard(expectedRange: range)
        let generation = selectionPollGeneration
        selectionTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollSelection(generation: generation) }
        }
        selectionTimer?.tolerance = 0.05
    }

    /// Withdraws the offer when Accessibility reports a different selection or focused element.
    private func pollSelection(generation: Int) {
        guard generation == selectionPollGeneration else { return }
        Task { [weak self] in await self?.pollFocusedSelection(generation: generation) }
    }

    /// Reads the focused selection and withdraws an armed offer when it no longer matches.
    func pollFocusedSelection(generation: Int? = nil) async {
        let generation = generation ?? selectionPollGeneration
        guard generation == selectionPollGeneration, !selectionPollInFlight,
            armedOffer != nil, selectionGuard != nil, !isInserting
        else { return }
        selectionPollInFlight = true
        let selection = await focusedSelectionReader()
        guard generation == selectionPollGeneration else { return }
        selectionPollInFlight = false
        guard var selectionGuard else { return }
        guard !selectionGuard.observe(selection) else { return withdraw() }
        self.selectionGuard = selectionGuard
    }

    /// Stops the selection poll and invalidates any result still waiting on Accessibility.
    private func stopWatchingSelection() {
        selectionPollGeneration += 1
        selectionTimer?.invalidate()
        selectionTimer = nil
        selectionGuard = nil
        selectionPollInFlight = false
        FocusedFieldReader.cancelFocusedSelectionRead()
    }

    /// Withdraws a ghost the scroll has left behind, once, and lets the clock redraw it where the caret now is.
    private func scrolled() {
        guard panel.isShowing else { return stopWatchingScrolls() }
        guard !isInserting else { return }
        noteActivity()
        withdraw()
    }

    /// Starts the pause clock if it is not running; every activity calls this.
    func noteActivity() {
        guard ticking.noteActivity(at: Date()) else { return }
        scheduleTicker(every: SuggestionTicking.interval)
    }

    /// Schedules field observation at the cadence for the current phase.
    private func scheduleTicker(every interval: TimeInterval) {
        ticker?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = min(SuggestionTicking.tolerance, interval / 5)
        ticker = timer
    }

    /// Wakes a turn while a field can change beneath a visible ghost.
    private func tick() {
        switch ticking.tick(at: Date(), ghostIsVisible: panel.isShowing) {
        case .wake:
            wake(.tick)
        case .wakeAndSlow:
            scheduleTicker(every: SuggestionTicking.ghostInterval)
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
    private func keyPressed(_ key: Key, typing text: String? = nil) {
        noteActivity()
        lastKeystroke = Date()
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

    /// Keeps the ghost up when the key typed its next letters, answering false for any other key, which withdraws it.
    private func typedThrough(_ text: String) -> Bool {
        guard panel.isShowing, !isInserting, let update = session.typedThrough(text) else { return false }
        // Whatever was being worked out was for the shorter line, and the turn woken below reads the new one.
        generating?.cancel()
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
    private func applicationChanged() {
        FocusedFieldReader.focusMayHaveMoved()
        noteActivity()
        withdraw()
        wake(.applicationChanged)
    }

    /// Books one turn for later, replacing any already booked, which is how a pause is answered the moment it is long enough.
    private func wake(_ reason: SuggestionReason, afterMilliseconds delay: Int) {
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
        guard !isDictating else { return }
        if reason == .keystroke || reason == .tick {
            let delay = Self.remainingFieldReadDebounce(sinceKeystroke: lastKeystroke, now: Date())
            if delay > 0 {
                wake(reason, afterMilliseconds: delay)
                return
            }
        }
        switch turns.begin(at: Date()) {
        case .busy:
            // A Return or a switch waiting its turn is never overwritten by the tick that follows it.
            if again.map({ reason.urgency > $0.urgency }) ?? true { again = reason }
        case .stalled(let turn):
            Self.log.error(
                "\(SuggestionLog.stall(step: self.progress?.step, application: self.progress?.application, afterSeconds: TurnGate.stallSeconds), privacy: .public)"
            )
            generating?.cancel()
            running?.cancel()
            start(turn, because: reason)
        case .free(let turn):
            start(turn, because: reason)
        }
    }

    /// Runs the turn the gate admitted and reports its end under the same number.
    private func start(_ turn: Int, because reason: SuggestionReason) {
        running = Task { [weak self] in
            await self?.turn(turn, because: reason)
            self?.finished(turn)
        }
    }

    /// Runs whatever arrived while the turn was in flight, unless the turn had already been left behind.
    private func finished(_ turn: Int) {
        guard turns.end(turn), let next = again else { return }
        again = nil
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

    /// Reads the field, asks the corpus and draws the answer, all off the keystroke path; a turn left behind touches nothing.
    private func turn(_ number: Int, because reason: SuggestionReason) async {
        await rejectedSuggestionRecorder.retry()
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        progress = (number, .read, front)
        // Taken before the read, since a key pressed while a slow field is being read is one the read may have missed.
        let keystrokesSeen = session.keystrokes
        let shouldRead = Self.shouldRead(
            front: front, own: ownBundleIdentifier, preferences: preferences, at: Date())
        let readStarted = Date()
        let read = shouldRead ? await FocusedFieldReader.read() : nil
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
            draw(session.turn(in: nil, at: PredictionContext(typed: "")).step)
            return
        }
        let started = Date()
        guard preferences.isEnabled(in: snapshot.bundleIdentifier, at: started) else {
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
        if !snapshot.isSecure {
            entering(.remember, turn: number)
            await remember(snapshot, as: reading, because: reason, at: started)
        }
        guard turns.isCurrent(number) else { return }
        lastReading = reading

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
            await rejectedSuggestionRecorder.record(rejected, in: surface)
        }

        switch turn.step {
        case .settled(let update):
            settle(update, in: snapshot, since: started)
        case .query(let query):
            entering(.corpus, turn: number)
            let candidates = await candidates(for: query)
            let ready = await generator?.isReady ?? false
            guard turns.isCurrent(number) else { return }
            panel.statusMessage =
                generator != nil && !ready
                ? "Suggestions are paused while Low Power Mode or thermal pressure is active."
                : nil
            Self.log.debug(
                "\(SuggestionLog.query(typed: query.typed, corpus: candidates.count, generatorReady: ready), privacy: .public)"
            )
            guard let update = await remembered(number, candidates, for: query, since: started),
                turns.isCurrent(number)
            else { return }
            // When nothing remembered can be drawn — nothing held, the line itself, or a line the gates refused — the model invents the suggestion instead.
            guard ModelPass.shouldAsk(after: update, hasGenerator: generator != nil, isReady: ready),
                let generator
            else {
                return settle(update, in: snapshot, since: started)
            }
            // The machine says first what the next word may be: anything, one of its values, or nothing here, which no pass can improve on.
            entering(.options, turn: number)
            let options = await verifier.options(for: query.typed, in: query.surface, now: Date())
            guard turns.isCurrent(number) else { return }
            switch options {
            case .none:
                Self.log.debug("\(SuggestionLog.optionsNone(typed: query.typed), privacy: .public)")
                modelPass.rememberEmpty(query, at: SuggestionMoment.place(of: snapshot))
                guard
                    let quiet = session.resolveGenerated(
                        [], for: query, elapsedMilliseconds: since(started), whenEmpty: .notOnThisMachine,
                        scores: [:])
                else { return }
                settle(quiet, in: snapshot, since: started)
            case .among(let values):
                Self.log.debug(
                    "\(SuggestionLog.optionsAmong(typed: query.typed, among: values.count), privacy: .public)"
                )
                await generate(
                    number, with: generator, for: query, in: snapshot, choosing: values, since: started)
            case .open:
                await generate(number, with: generator, for: query, in: snapshot, since: started)
            }
        }
    }

    /// Draws the update and, when it draws nothing, says why, so a silence is never logged without its reason.
    private func settle(_ update: SuggestionUpdate, in snapshot: FocusedFieldSnapshot, since started: Date) {
        if let silence = update.silence {
            Self.log.debug(
                "\(SuggestionLog.quiet(typed: snapshot.currentLine, reason: silence.rawValue, rejections: self.session.rejectionsHere, silencedHere: self.session.isSilencedHere, enabled: self.session.isEnabled), privacy: .public)"
            )
            // A prose pause is answered the moment it is long enough, rather than at whatever tick comes next.
            if silence == .writingFluently {
                let delay = Self.hesitationWake(sinceKeystroke: lastKeystroke, now: Date())
                wake(.tick, afterMilliseconds: delay)
            }
        }
        panel.statusMessage = nil
        draw(update, in: snapshot)
    }

    /// What the corpus and the gates make of the line: the update they settle on, or nothing once the turn was left behind.
    private func remembered(
        _ number: Int, _ candidates: [Candidate], for query: SuggestionQuery, since started: Date
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
        guard let fresh = await FocusedFieldReader.read(), turns.isCurrent(number),
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
        in snapshot: FocusedFieldSnapshot, choosing choices: [String] = [], since started: Date
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
            generating = pass
            entering(.generate, turn: number)
            let answer = await pass.result
            generating = nil
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
        guard update.silence == nil else { return settle(update, in: snapshot, since: started) }
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
        generating = more
        entering(.alternatives, turn: number)
        let followUp = await more.result
        generating = nil
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
        let standing = await verifier.standing(lines, after: query.typed, in: query.surface, now: Date())
        if standing.count < lines.count {
            Self.log.debug(
                "\(SuggestionLog.attest(typed: query.typed, offered: lines.count, standing: standing.count), privacy: .public)"
            )
        }
        return standing
    }

    /// Milliseconds until the prose pause after the latest keystroke is long enough, counted from now rather than from the turn's start.
    nonisolated static func hesitationWake(sinceKeystroke keystroke: Date, now: Date) -> Int {
        let passed = Int(now.timeIntervalSince(keystroke) * 1000)
        return max(0, Quieting.proseHesitationInMilliseconds - passed) + 20
    }

    /// What is left of the debounce for a key pressed at `keystroke`, which is nothing once the pause is long enough.
    nonisolated static func remainingDebounce(sinceKeystroke keystroke: Date, now: Date) -> Duration {
        let passed = now.timeIntervalSince(keystroke) * 1000
        return .milliseconds(max(0, Double(Self.generationDebounceInMilliseconds) - passed))
    }

    /// Milliseconds left before typing has paused long enough to read the field.
    nonisolated static func remainingFieldReadDebounce(sinceKeystroke keystroke: Date, now: Date) -> Int {
        let passed = now.timeIntervalSince(keystroke) * 1000
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
        _ number: Int, _ request: VerificationRequest, since started: Date
    ) async -> SuggestionUpdate? {
        let allowed = await verifier.verified(
            request.candidates, in: request.surface, typed: request.typed, now: Date())
        guard turns.isCurrent(number) else { return nil }
        Self.log.debug(
            "\(SuggestionLog.verify(typed: request.typed, offered: request.candidates.count, allowed: allowed.count, elapsedMilliseconds: self.since(started), firstCompletion: allowed.first?.text), privacy: .public)"
        )
        // The gates answer within a moment, so the field read at the turn's start still stands for whatever is drawn.
        return session.resolve(allowed, for: request, now: Date(), elapsedMilliseconds: since(started))
    }

    /// How long this turn has taken, which is what decides whether its answer is still worth drawing.
    private func since(_ started: Date) -> Int {
        Int(Date().timeIntervalSince(started) * 1000)
    }

    /// What the corpus remembers, or failing that what this machine holds; the machine never outranks the person's own history.
    func candidates(for query: SuggestionQuery) async -> [Candidate] {
        let candidates = await CandidateSources.candidates(
            from: store, environment: environment, for: query.surface, matching: query.typed, now: Date())
        return candidates.filter {
            !rejectedSuggestionRecorder.suppresses($0.text, in: query.surface)
        }
    }

    /// Tells capture what happened, and asks the user once about an application it has not met.
    private func remember(
        _ snapshot: FocusedFieldSnapshot, as reading: FieldReading, because reason: SuggestionReason,
        at moment: Date
    ) async {
        // The acceptance is recorded off the key path, and capture still hears of it before this event.
        await acceptances.drained()
        var typed = pendingCaptureTyping
        pendingCaptureTyping = []
        if case .applicationChanged = reason, let leaving = lastReading, leaving != reading {
            for input in typed {
                _ = try? await capture.handle(.typed(input, at: moment), in: leaving)
            }
            typed = []
            _ = try? await capture.handle(.applicationDeactivated(at: moment), in: leaving)
        }
        let line = snapshot.learnableLine
        var events: [CaptureEvent]
        if case .returnPressed = reason {
            let prior = handed.flatMap { $0.reading == reading ? $0.line : nil } ?? ""
            events = ReturnCatchUp.events(read: line, handed: prior, at: moment)
            handed = nil
        } else {
            events = [reason.event(holding: line, at: moment)]
            if case .keystroke = events[0] { handed = (line, reading) }
        }
        events.insert(contentsOf: typed.map { .typed($0, at: moment) }, at: 0)
        // Only a turn that read the line can tell capture the line holds inserted text.
        if insertionPending, reason != .tick {
            insertionPending = false
            events = CaptureEvent.marking(events, insertedAt: moment)
        }
        var outcome: CaptureOutcome?
        for event in events { outcome = try? await capture.handle(event, in: reading) }
        guard let outcome else { return }
        guard case .refused(let refusal) = outcome, refusal.asksTheUser else { return }
        // The Suggestions screen has already said yes to this application, so the capture store is told so.
        Task { [capture] in try? await capture.record(.allowed, for: snapshot.bundleIdentifier) }
    }

    // MARK: Drawing

    /// Draws whatever a turn with no field behind it settled on, which is always nothing.
    private func draw(_ step: SuggestionStep) {
        guard !isStopped, !isPointerGestureActive, !nativeMenuIsOpen,
            case .settled(let update) = step
        else { return }
        panel.statusMessage = nil
        stopWatchingSelection()
        interceptor.arm(update.armed)
        armedOffer = update.suggestion.accepting
        panel.hide()
        lastReading = nil
    }

    /// Arms the tap first and draws second, so no key is claimed that nothing is offering.
    func draw(_ update: SuggestionUpdate, in snapshot: FocusedFieldSnapshot?) {
        // A stopped loop, a held pointer gesture, or a stale read draws nothing and claims no key.
        guard !isStopped, !isPointerGestureActive, !nativeMenuIsOpen, session.isCurrent else {
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
        armSelectionMonitor(for: update.suggestion, at: snapshot.selection)
        watchScrolls()
    }

    /// The caret a ghost for `suggestion` is drawn at, or nil when the field offers no inline place for one.
    nonisolated static func caret(for suggestion: Suggestion, in snapshot: FocusedFieldSnapshot) -> CGRect? {
        guard suggestion != .silent, snapshot.placement == .inlineGhost else { return nil }
        return snapshot.caret
    }

    /// Draws what a move or a dismissal left where the ghost already stands, since no field was read for it and typing may have moved it.
    private func redraw(_ update: SuggestionUpdate) {
        guard !isStopped, !isPointerGestureActive, !nativeMenuIsOpen, session.isCurrent else {
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
            let reading = lastReading
            let action = session.route(stroke)
            Self.log.debug(
                "SWALLOWED key=\(String(describing: stroke.key), privacy: .public) modifiers=\(stroke.modifiers.rawValue) decision=\(Self.name(of: action), privacy: .public)"
            )
            switch action {
            case .accept(let text):
                stopWatchingSelection()
                panel.hide()
                interceptor.arm([])
                generating?.cancel()
                // Held across the insert so the keys it posts are ignored on both the tap and the monitor.
                isInserting = true
                let returnedKey = await Self.acceptKeyToReturnIfTakeFails(stroke) {
                    await take(
                        text, after: typed, in: reading,
                        closingPunctuation: closingPunctuationAfterCaret)
                }
                isInserting = false
                // A field that is no longer the drawn line gets its key back, so Tab still does what Tab does there.
                if let returnedKey { KeyStrokeReturn.post(returnedKey) }
                noteActivity()
                // The field is re-read a moment later, since an application applies the insertion after the keys land.
                wake(.tick, afterMilliseconds: 80)
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
        tapRest.schedule(after: .seconds(Self.tapRestSeconds)) { [weak self] in
            guard let self, !isStopped else { return }
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

    /// Returns the swallowed accept stroke only when taking the suggestion fails.
    static func acceptKeyToReturnIfTakeFails(
        _ stroke: UttrflowPredict.KeyStroke, taking: () async -> Bool
    ) async -> UttrflowPredict.KeyStroke? {
        await taking() ? nil : stroke
    }

    /// Puts the tail into the field and queues the taken line for capture, answering false when the field refused it unwritten.
    private func take(
        _ text: String, after typed: String, in reading: FieldReading?, closingPunctuation: String
    ) async -> Bool {
        // What the gates left is a whole line, so taking it may replace characters as well as add.
        guard let windowNumber = reading?.surface?.windowNumber else {
            Self.log.error("the drawn field has no identifiable window; giving the key back")
            return false
        }
        var via = "nothing"
        let accepted = Suggestion.certain(text).trimmed(
            after: typed, matching: closingPunctuation)
        do throws(TextInsertionError) {
            via =
                try await acceptor.accept(
                    accepted, after: typed, expectedWindowNumber: windowNumber)?.rawValue ?? via
        } catch {
            Self.log.error("\(SuggestionLog.landedNowhere(error, typed: typed), privacy: .public)")
            return false
        }
        Self.log.debug(
            "\(SuggestionLog.accept(text: text, typed: typed, via: via), privacy: .public)"
        )
        guard let reading else { return true }
        let moment = Date()
        let log = Self.log
        acceptances.enqueue { [capture] in
            do {
                _ = try await capture.accepted(text, over: typed, in: reading, at: moment)
            } catch {
                // The session holds the acceptance and retries it before the next event.
                log.error("An accepted suggestion's corpus write failed and is held for a retry")
            }
        }
        return true
    }

    // MARK: Consent

    /// What the field publishes about itself, in the shape the corpus keys entries by.
    private func reading(of snapshot: FocusedFieldSnapshot) -> FieldReading {
        SuggestionMoment.reading(of: snapshot)
    }

    /// Everything about this moment that can silence a suggestion.
    private func context(of snapshot: FocusedFieldSnapshot, at moment: Date) -> PredictionContext {
        SuggestionMoment.context(
            of: snapshot, millisecondsSinceKeystroke: Int(moment.timeIntervalSince(lastKeystroke) * 1000))
    }
}
