import AppKit
import Foundation
import OSLog
import UttrflowContext
import UttrflowInput
import UttrflowPredict
import UttrflowPredictCapture
import UttrflowPredictStore

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
    /// Says why nothing is being suggested, which silence alone cannot.
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "predict")

    /// How often the field is re-read with nothing else happening, which is what notices a pause.
    private static let tickInterval: TimeInterval = 1

    private let store: PredictStore
    private let capture: CaptureSession
    private let panel = SuggestionPanelController()
    private let interceptor = KeyInterceptor()
    private let acceptor: SuggestionAcceptor
    /// What the user has decided on the Suggestions screen, which the app hands over as it changes.
    private var preferences: SuggestionPreferences
    /// What exists on this machine right now, which the corpus cannot know. See `Docs/predict.md`.
    private let environment: EnvironmentSource
    /// The gates that decide whether a candidate is right, which is not what the ranking measures.
    private let verifier: Verifier
    /// The model that invents a suggestion when the corpus has none, absent until the app hands one over.
    private let generator: (any CandidateGenerating)?

    private var session = SuggestionSession()
    private var monitors: [Any] = []
    private var activations: (any NSObjectProtocol)?
    private var ticker: Timer?
    private var swallowed: Task<Void, Never>?
    private var lastReading: FieldReading?
    /// The last field read, so the highlight can move without reading anything again.
    private var lastSnapshot: FocusedFieldSnapshot?
    private var lastKeystroke = Date.distantPast
    private var running = false
    /// True while an accepted completion is being inserted, so the keys it posts wake no further turn.
    private var isInserting = false
    private var again: SuggestionReason?
    /// Applications already asked about this launch, so a declined question is not repeated.
    private var asked: Set<String> = []
    private let ownBundleIdentifier = Bundle.main.bundleIdentifier
    /// Called when the user turns the feature off everywhere, so the choice is persisted and can be undone.
    var onTurnedOffEverywhere: (() -> Void)?

    /// Opens the corpus, or reports why it could not; the scorer, when given, is the model that validates.
    init(
        container: URL, preferences: SuggestionPreferences,
        scoring: (any CandidateScoring)? = nil, generating: (any CandidateGenerating)? = nil
    ) throws(PredictStoreError) {
        self.preferences = preferences
        self.generator = generating
        let store = try PredictStore(
            path: PredictStore.defaultFile(in: container).path(percentEncoded: false))
        self.store = store
        // One index behind both, so asking the machine for a completion also warms what attests it.
        let index = EnvironmentIndex(reader: SystemEnvironmentReader())
        environment = EnvironmentSource(index: index)
        // The model, when the app hands one over, is what turns a habit into a validated suggestion.
        verifier = Verifier(index: index, scoring: scoring, supersession: store)
        capture = CaptureSession(
            sink: store,
            preferencesFile: CapturePreferencesFile(
                path: CapturePreferencesFile.defaultFile(in: container).path(percentEncoded: false)))
        acceptor = SuggestionAcceptor(completion: TextInsertion.completion())
    }

    isolated deinit {
        stop()
    }

    /// Takes what the user has just chosen, so a change on the Suggestions screen holds from the next keystroke.
    func follow(_ preferences: SuggestionPreferences) {
        self.preferences = preferences
    }

    /// Arms the tap and starts watching, or says why it cannot.
    func start() {
        do {
            try interceptor.start()
        } catch {
            Self.log.error("tab-to-complete is off: \(String(describing: error), privacy: .public)")
            return
        }
        interceptor.arm([])
        // Before the first keystroke, because the reader's queue may not call AppKit or HIToolbox.
        FocusedFieldReader.prepare()
        watchSwallowedKeys()
        watchForActivity()
    }

    /// Takes the surface away, disarms the tap and stops watching.
    func stop() {
        interceptor.arm([])
        interceptor.stop()
        panel.hide()
        swallowed?.cancel()
        swallowed = nil
        ticker?.invalidate()
        ticker = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        if let activations { NSWorkspace.shared.notificationCenter.removeObserver(activations) }
        activations = nil
    }

    // MARK: What wakes the loop

    /// Keystrokes elsewhere, the application in front changing, and a clock for the pauses.
    private func watchForActivity() {
        let keys = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            // A key this app inserted must not wake another turn, or the feature types on its own.
            if let cgEvent = event.cgEvent, SyntheticEvent.isOurs(cgEvent) { return }
            MainActor.assumeIsolated { self?.keyPressed(Key(keyCode: event.keyCode)) }
        }
        if let keys { monitors.append(keys) }
        activations = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.wake(.applicationChanged) }
        }
        ticker = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) {
            [weak self] _ in MainActor.assumeIsolated { self?.wake(.tick) }
        }
    }

    /// One key pressed in another application, which is the only thing that moves the caret for us.
    private func keyPressed(_ key: Key) {
        // Keys arriving while we insert are our own, so they neither reset the pause clock nor wake a turn.
        guard !isInserting else { return }
        lastKeystroke = Date()
        wake(key == .return ? .returnPressed : .keystroke)
    }

    /// Runs one turn, or notes that another is wanted, so two never run at once.
    private func wake(_ reason: SuggestionReason) {
        guard !running else {
            again = reason
            return
        }
        running = true
        Task { [weak self] in
            await self?.turn(because: reason)
            self?.finished()
        }
    }

    /// Runs whatever arrived while the last turn was in flight.
    private func finished() {
        running = false
        guard let next = again else { return }
        again = nil
        wake(next)
    }

    // MARK: One turn

    /// Reads the field, asks the corpus and draws the answer, all off the keystroke path.
    private func turn(because reason: SuggestionReason) async {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != ownBundleIdentifier,
            let snapshot = await FocusedFieldReader.read()
        else {
            draw(session.turn(in: nil, at: PredictionContext(typed: "")).step)
            return
        }
        // The clock starts after the field read, so the cross-process read is not charged against the budget.
        let started = Date()
        guard preferences.isEnabled(in: snapshot.bundleIdentifier, at: started) else {
            draw(session.turn(in: nil, at: PredictionContext(typed: "")).step)
            return
        }

        let reading = reading(of: snapshot)
        // A password field is refused here, before its value has been passed to anything at all.
        if !snapshot.isSecure { await remember(snapshot, as: reading, because: reason, at: started) }
        lastReading = reading
        lastSnapshot = snapshot

        let turn = session.turn(
            in: reading.surface, at: context(of: snapshot, at: started),
            acceptKey: preferences.acceptKeys.key(forBundleIdentifier: snapshot.bundleIdentifier),
            isQuiet: preferences.isQuiet)
        if let rejected = turn.rejected, let surface = reading.surface {
            try? await store.recordRejected(rejected, in: surface)
        }

        switch turn.step {
        case .settled(let update):
            draw(update, in: snapshot)
        case .query(let query):
            let candidates = await candidates(for: query)
            // With nothing remembered for this line, the model invents the suggestion instead.
            if candidates.isEmpty, let generator, await generator.isReady {
                await generate(with: generator, for: query, in: snapshot, since: started)
                return
            }
            switch session.resolve(
                candidates, for: query, now: Date(), elapsedMilliseconds: since(started))
            {
            case .settled(let update):
                draw(update, in: snapshot)
            case .verify(let request):
                await verify(request, in: snapshot, since: started)
            case nil:
                return
            }
        }
    }

    /// Asks the model for a suggestion the corpus never held, from the field read live, and draws it.
    private func generate(
        with generator: any CandidateGenerating, for query: SuggestionQuery,
        in snapshot: FocusedFieldSnapshot, since started: Date
    ) async {
        let situation = GenerationSituation(
            application: snapshot.applicationName,
            field: snapshot.accessibilityDescription ?? snapshot.placeholder ?? snapshot.role,
            document: snapshot.document)
        let completions = await generator.completions(for: query.typed, in: situation)
        guard
            let update = session.resolveGenerated(
                completions, for: query, elapsedMilliseconds: since(started))
        else { return }
        draw(update, in: snapshot)
    }

    /// Puts the head of the ranking through the gates and draws whatever survives them.
    private func verify(
        _ request: VerificationRequest, in snapshot: FocusedFieldSnapshot, since started: Date
    ) async {
        let allowed = await verifier.verified(
            request.candidates, in: request.surface, typed: request.typed, now: Date())
        guard
            let update = session.resolve(
                allowed, for: request, now: Date(), elapsedMilliseconds: since(started))
        else { return }
        draw(update, in: snapshot)
    }

    /// How long this turn has taken, which is what decides whether its answer is still worth drawing.
    private func since(_ started: Date) -> Int {
        Int(Date().timeIntervalSince(started) * 1000)
    }

    /// What the corpus remembers and what this machine holds, which never waits on a read.
    private func candidates(for query: SuggestionQuery) async -> [Candidate] {
        let remembered =
            (try? await store.candidates(for: query.surface, matching: query.typed)) ?? []
        let here = await environment.candidates(
            for: query.surface, matching: query.typed, now: Date())
        return remembered + here
    }

    /// Tells capture what happened, and asks the user once about an application it has not met.
    private func remember(
        _ snapshot: FocusedFieldSnapshot, as reading: FieldReading, because reason: SuggestionReason,
        at moment: Date
    ) async {
        if case .applicationChanged = reason, let leaving = lastReading, leaving != reading {
            _ = try? await capture.handle(.applicationDeactivated(at: moment), in: leaving)
        }
        let event = reason.event(holding: snapshot.currentLine, at: moment)
        guard let outcome = try? await capture.handle(event, in: reading) else { return }
        guard case .refused(let refusal) = outcome, refusal.asksTheUser else { return }
        await askAboutLearning(from: snapshot)
    }

    // MARK: Drawing

    /// Draws whatever a turn with no field behind it settled on, which is always nothing.
    private func draw(_ step: SuggestionStep) {
        guard case .settled(let update) = step else { return }
        interceptor.arm(update.armed)
        panel.hide()
        lastReading = nil
        lastSnapshot = nil
    }

    /// Arms the tap first and draws second, so no key is claimed that nothing is offering.
    private func draw(_ update: SuggestionUpdate, in snapshot: FocusedFieldSnapshot?) {
        interceptor.arm(update.armed)
        // Nothing is drawn off the caret's line, so a field that reports no inline placement is left alone.
        guard update.suggestion != .silent, let snapshot, snapshot.placement == .inlineGhost,
            let caret = snapshot.caret
        else {
            panel.hide()
            return
        }
        panel.show(
            update.suggestion, typed: session.typed, placement: .inlineGhost, caret: caret,
            window: snapshot.window, fieldPointSize: snapshot.pointSize,
            selection: session.selection.index)
    }

    // MARK: Accepting

    /// Every key the tap took, decided in the session and carried out here.
    private func watchSwallowedKeys() {
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
            stop()
        case .swallowed(let stroke):
            let typed = session.typed
            let surface = session.surface
            switch session.route(stroke) {
            case .accept(let text):
                panel.hide()
                interceptor.arm([])
                // Held across the insert so the keys it posts are ignored on both the tap and the monitor.
                isInserting = true
                await take(text, after: typed, in: surface)
                isInserting = false
                wake(.keystroke)
            case .redraw(let update):
                draw(update, in: lastSnapshot)
            case .nothing:
                break
            }
            // ⌥⎋ turns the feature off everywhere; persist it so the switch agrees and a later enable rebuilds this.
            if !session.isEnabled {
                if let onTurnedOffEverywhere { onTurnedOffEverywhere() } else { stop() }
            }
        }
    }

    /// Puts the tail into the field and counts the acceptance, which the corpus discounts.
    private func take(_ text: String, after typed: String, in surface: Surface?) async {
        do {
            // What the gates left is a whole line, so taking it may replace characters as well as add.
            try await acceptor.accept(.certain(text), after: typed)
        } catch {
            Self.log.error("a completion landed nowhere: \(error.userMessage, privacy: .public)")
            return
        }
        guard let surface else { return }
        try? await store.recordAccepted(text, in: surface)
        try? await store.record(text, in: surface, selfSourced: true, at: Date())
    }

    // MARK: Consent

    /// Asks once whether this application may be learned from, and remembers the answer.
    private func askAboutLearning(from snapshot: FocusedFieldSnapshot) async {
        guard asked.insert(snapshot.bundleIdentifier).inserted else { return }
        let alert = NSAlert()
        alert.messageText = "Let Uttrflow finish what you type in \(snapshot.applicationName)?"
        alert.informativeText =
            "What you enter there is kept on this Mac, in Uttrflow's own folder, and is never uploaded."
        alert.addButton(withTitle: "Learn Here")
        alert.addButton(withTitle: "Not Here")
        NSApplication.shared.activate()
        let allowed = alert.runModal() == .alertFirstButtonReturn
        try? await capture.record(allowed ? .allowed : .declined, for: snapshot.bundleIdentifier)
    }

    /// What the field publishes about itself, in the shape the corpus keys entries by.
    private func reading(of snapshot: FocusedFieldSnapshot) -> FieldReading {
        FieldReading(
            bundleIdentifier: snapshot.bundleIdentifier, role: snapshot.role,
            subrole: snapshot.subrole, identifier: snapshot.identifier,
            placeholder: snapshot.placeholder,
            accessibilityDescription: snapshot.accessibilityDescription, document: snapshot.document)
    }

    /// Everything about this moment that can silence a suggestion.
    private func context(of snapshot: FocusedFieldSnapshot, at moment: Date) -> PredictionContext {
        PredictionContext(
            typed: snapshot.currentLine, caretAtLineEnd: snapshot.caretAtLineEnd,
            hasSelection: snapshot.hasSelection, isComposing: snapshot.isComposing,
            isSecure: snapshot.isSecure, isProse: snapshot.isProse,
            millisecondsSinceKeystroke: Int(moment.timeIntervalSince(lastKeystroke) * 1000))
    }
}
