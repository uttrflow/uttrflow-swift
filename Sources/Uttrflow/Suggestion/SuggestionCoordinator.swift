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
    /// The model's last answer, reused for as long as the line still begins one of its lines, so typing on or back costs no pass.
    private var lastGenerated: (surface: Surface, typed: String, completions: [String])?
    /// The model pass in flight, cancelled by the next keystroke so a burst never queues one pass per key.
    private var generating: Task<[String], any Error>?
    /// The line the model last had nothing for, or failed on, so a tick does not ask the same question again until the line changes.
    private var lastEmpty: (surface: Surface, typed: String)?
    /// A turn booked for the moment a rule stops refusing, so a prose pause is answered then, not at the next tick.
    private var pendingWake: Task<Void, Never>?
    /// How long a burst of keystrokes must pause before the model is asked about its last prefix.
    private static let generationDebounceInMilliseconds = 120
    /// How much of the text before the caret's line the model is shown, enough for the sentence or command before it.
    private static let precedingContextLength = 400
    /// How many of this person's recent lines in the field the model is shown, enough to hear their voice in it.
    private static let recentLinesShown = 6

    private var session = SuggestionSession()
    private var monitors: [Any] = []
    private var activations: (any NSObjectProtocol)?
    private var ticker: Timer?
    private var swallowed: Task<Void, Never>?
    private var lastReading: FieldReading?
    /// The last field read, so the highlight can move without reading anything again.
    private var lastSnapshot: FocusedFieldSnapshot?
    private var lastKeystroke = Date.distantPast
    /// One turn at a time, with a turn that never returns left behind so the loop cannot die with it.
    private var turns = TurnGate()
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
                path: CapturePreferencesFile.defaultFile(in: container).path(percentEncoded: false)),
            // A shell line that was not run was not a command, so a terminal learns only what Return finished.
            policy: CommitPolicy { reason, reading in
                !TerminalApplications.contains(reading.bundleIdentifier) || reason == .returnPressed
            })
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
        generating?.cancel()
        pendingWake?.cancel()
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
        // A click moves the caret or the focus without a key, so it wakes a turn the way a pause does.
        let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.wake(.tick) }
        }
        if let clicks { monitors.append(clicks) }
        activations = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applicationChanged() }
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
        // The line just changed, so a pass about its old prefix and a wake booked for it are both stale.
        generating?.cancel()
        pendingWake?.cancel()
        wake(key == .return ? .returnPressed : .keystroke)
    }

    /// Another application came to the front, so whatever was being worked out for the last field is stale now.
    private func applicationChanged() {
        generating?.cancel()
        pendingWake?.cancel()
        interceptor.arm([])
        panel.hide()
        wake(.applicationChanged)
    }

    /// Books one turn for later, replacing any already booked, which is how a pause is answered the moment it is long enough.
    private func wake(_ reason: SuggestionReason, afterMilliseconds delay: Int) {
        pendingWake?.cancel()
        pendingWake = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(max(delay, 1)))
            guard !Task.isCancelled else { return }
            self?.wake(reason)
        }
    }

    /// Runs one turn, or notes that another is wanted, so two never run at once and a stuck one never ends the loop.
    private func wake(_ reason: SuggestionReason) {
        switch turns.begin(at: Date()) {
        case .busy:
            // A Return or a switch waiting its turn is never overwritten by the tick that follows it.
            if again.map({ reason.urgency > $0.urgency }) ?? true { again = reason }
        case .stalled(let turn):
            Self.log.error("STALL a turn ran past \(TurnGate.stallSeconds)s and is left behind")
            generating?.cancel()
            start(turn, because: reason)
        case .free(let turn):
            start(turn, because: reason)
        }
    }

    /// Runs the turn the gate admitted and reports its end under the same number.
    private func start(_ turn: Int, because reason: SuggestionReason) {
        Task { [weak self] in
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

    // MARK: One turn

    /// Reads the field, asks the corpus and draws the answer, all off the keystroke path; a turn left behind touches nothing.
    private func turn(_ number: Int, because reason: SuggestionReason) async {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        let read = front == ownBundleIdentifier ? nil : await FocusedFieldReader.read()
        guard turns.isCurrent(number) else { return }
        Self.log.debug(
            "TURN front=\(front, privacy: .public) read=\(read != nil) line=\(read?.currentLine ?? "-", privacy: .public) value=\(read?.value != nil) caret=\(read?.caret != nil) secure=\(read?.isSecure ?? false) placement=\(String(describing: read?.placement), privacy: .public)"
        )
        guard front != ownBundleIdentifier, let snapshot = read else {
            draw(session.turn(in: nil, at: PredictionContext(typed: "")).step)
            return
        }
        // The clock starts after the field read, so the cross-process read is not charged against the budget.
        let started = Date()
        guard preferences.isEnabled(in: snapshot.bundleIdentifier, at: started) else {
            Self.log.debug(
                "OFF app=\(snapshot.bundleIdentifier, privacy: .public) not enabled in Suggestions")
            draw(session.turn(in: nil, at: PredictionContext(typed: "")).step)
            return
        }

        let reading = reading(of: snapshot)
        // A new field or an emptied line is a fresh start: nothing drawn, no key held, nothing remembered of the last line.
        if reading.surface != session.surface {
            interceptor.arm([])
            panel.hide()
        }
        if reading.surface != session.surface || snapshot.currentLine.isEmpty {
            lastGenerated = nil
            lastEmpty = nil
        }
        // A password field is refused here, before its value has been passed to anything at all.
        if !snapshot.isSecure { await remember(snapshot, as: reading, because: reason, at: started) }
        guard turns.isCurrent(number) else { return }
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
            // The session names why nothing is offered, so silence is never logged without its reason.
            if let silence = update.silence {
                Self.log.debug(
                    "QUIET typed=\(snapshot.currentLine, privacy: .public) reason=\(silence.rawValue, privacy: .public) rejections=\(self.session.rejectionsHere) silencedHere=\(self.session.isSilencedHere) enabled=\(self.session.isEnabled)"
                )
                // A prose pause is answered the moment it is long enough, rather than at whatever tick comes next.
                if silence == .writingFluently {
                    let waited = Int(started.timeIntervalSince(lastKeystroke) * 1000)
                    wake(.tick, afterMilliseconds: Quieting.proseHesitationInMilliseconds - waited + 20)
                }
            }
            draw(update, in: snapshot)
        case .query(let query):
            let candidates = await candidates(for: query)
            let ready = await generator?.isReady ?? false
            guard turns.isCurrent(number) else { return }
            Self.log.debug(
                "QUERY typed=\(query.typed, privacy: .public) corpus=\(candidates.count) generatorReady=\(ready)"
            )
            // With nothing remembered for this line, the model invents the suggestion instead.
            if candidates.isEmpty, let generator, ready {
                await generate(number, with: generator, for: query, in: snapshot, since: started)
                return
            }
            switch session.resolve(
                candidates, for: query, now: Date(), elapsedMilliseconds: since(started))
            {
            case .settled(let update):
                draw(update, in: snapshot)
            case .verify(let request):
                await verify(number, request, in: snapshot, since: started)
            case nil:
                return
            }
        }
    }

    /// Draws an answer that took a while against the field as it is now, so a scrolled or moved caret is followed and a changed line is not written over.
    private func drawFresh(
        _ update: SuggestionUpdate, for snapshot: FocusedFieldSnapshot, turn number: Int
    ) async {
        guard let fresh = await FocusedFieldReader.read(), turns.isCurrent(number),
            reading(of: fresh) == reading(of: snapshot), fresh.currentLine == snapshot.currentLine
        else { return }
        lastSnapshot = fresh
        draw(update, in: fresh)
    }

    /// Asks the model for a suggestion the corpus never held, from the field read live, and draws it.
    private func generate(
        _ number: Int, with generator: any CandidateGenerating, for query: SuggestionQuery,
        in snapshot: FocusedFieldSnapshot, since started: Date
    ) async {
        let completions: [String]
        let lowered = query.typed.lowercased()
        // What the model already said about this line still holds while the line begins one of its answers.
        let kept =
            (lastGenerated?.surface == query.surface ? lastGenerated?.completions : nil)?
            .filter { $0.lowercased().hasPrefix(lowered) && $0 != query.typed } ?? []
        if !kept.isEmpty {
            completions = kept
        } else if let lastEmpty, lastEmpty.surface == query.surface, lastEmpty.typed == query.typed {
            // The model's last word on this exact line was nothing, and a tick changes nothing about the line.
            return
        } else {
            let pass = Task { [generator, store] in
                // A short quiet first, so a burst of keystrokes costs one pass for its last prefix rather than one per key.
                try? await Task.sleep(for: .milliseconds(Self.generationDebounceInMilliseconds))
                guard !Task.isCancelled else { return [String]() }
                // The context is read only once a pass is certain, so a cancelled burst never pays for it.
                let situation = await Self.situation(of: snapshot, for: query, store: store)
                return try await generator.completions(for: query.typed, in: situation)
            }
            generating = pass
            let answer = await pass.result
            generating = nil
            // A pass the next keystroke cancelled, or a turn left behind, answers a line that is gone: nothing is drawn or kept.
            guard !pass.isCancelled, turns.isCurrent(number) else { return }
            switch answer {
            case .failure(let error):
                // A failed pass is remembered like an empty one, so a tick never re-runs the failure, but it is never logged as one.
                lastEmpty = (query.surface, query.typed)
                Self.log.error(
                    "GENERATE failed typed=\(query.typed, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
                return
            case .success(let lines) where lines.isEmpty:
                // An empty answer is remembered against this exact line only, so the next keystroke asks afresh.
                lastEmpty = (query.surface, query.typed)
                completions = lines
            case .success(let lines):
                lastGenerated = (query.surface, query.typed, lines)
                completions = lines
            }
        }
        Self.log.debug(
            "GENERATE app=\(snapshot.applicationName, privacy: .public) typed=\(query.typed, privacy: .public) got=\(completions.count) elapsed=\(self.since(started))ms first=\(completions.first ?? "-", privacy: .public)"
        )
        guard
            let update = session.resolveGenerated(
                completions, for: query, elapsedMilliseconds: since(started))
        else { return }
        await drawFresh(update, for: snapshot, turn: number)
        // With the one line on screen, the others are fetched behind it, so Down has a list and the person never waited for it.
        guard completions.count == 1, let leader = completions.first, turns.isCurrent(number) else { return }
        let more = Task { [generator, store] in
            let situation = await Self.situation(of: snapshot, for: query, store: store)
            return try await generator.alternatives(for: query.typed, in: situation, excluding: leader)
        }
        generating = more
        let followUp = await more.result
        generating = nil
        guard !more.isCancelled, turns.isCurrent(number) else { return }
        guard case .success(let others) = followUp else {
            // The one line stays on screen; only the list behind it is missing, and the log says why.
            if case .failure(let error) = followUp {
                Self.log.error(
                    "ALTERNATIVES failed typed=\(query.typed, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
            return
        }
        guard !others.isEmpty, let expanded = session.expandGenerated(others, for: query) else { return }
        lastGenerated = (query.surface, query.typed, [leader] + others)
        Self.log.debug(
            "ALTERNATIVES typed=\(query.typed, privacy: .public) got=\(others.count) elapsed=\(self.since(started))ms"
        )
        await drawFresh(expanded, for: snapshot, turn: number)
    }

    /// Everything the model is told about the moment: the field, what is on screen around it, and how this person writes here.
    private static func situation(
        of snapshot: FocusedFieldSnapshot, for query: SuggestionQuery, store: PredictStore
    ) async -> GenerationSituation {
        let around = await FocusedFieldReader.surroundings()
        let recent = (try? await store.recent(in: query.surface, limit: Self.recentLinesShown)) ?? []
        // Lengths only, since what is on screen and what the person wrote are theirs and stay out of the log.
        Self.log.debug(
            "CONTEXT title=\(around?.windowTitle?.count ?? 0) around=\(around?.text?.count ?? 0) recent=\(recent.count) preceding=\(snapshot.preceding(maxLength: Self.precedingContextLength)?.count ?? 0)"
        )
        return GenerationSituation(
            application: snapshot.applicationName,
            field: snapshot.accessibilityDescription ?? snapshot.placeholder ?? snapshot.role,
            document: snapshot.document,
            preceding: snapshot.preceding(maxLength: Self.precedingContextLength),
            windowTitle: around?.windowTitle, surroundings: around?.text, recentLines: recent,
            isMultiline: snapshot.role == FocusedFieldSnapshot.proseRole
                || snapshot.value?.contains(where: \.isNewline) == true)
    }

    /// Puts the head of the ranking through the gates and draws whatever survives them.
    private func verify(
        _ number: Int, _ request: VerificationRequest, in snapshot: FocusedFieldSnapshot, since started: Date
    ) async {
        let allowed = await verifier.verified(
            request.candidates, in: request.surface, typed: request.typed, now: Date())
        guard turns.isCurrent(number) else { return }
        Self.log.debug(
            "VERIFY typed=\(request.typed, privacy: .public) in=\(request.candidates.count) out=\(allowed.count) elapsed=\(self.since(started))ms first=\(allowed.first?.text ?? "-", privacy: .public)"
        )
        guard
            let update = session.resolve(
                allowed, for: request, now: Date(), elapsedMilliseconds: since(started))
        else { return }
        // The gates answer within a moment, so the field read at the turn's start still stands.
        draw(update, in: snapshot)
    }

    /// How long this turn has taken, which is what decides whether its answer is still worth drawing.
    private func since(_ started: Date) -> Int {
        Int(Date().timeIntervalSince(started) * 1000)
    }

    /// What the corpus remembers, or failing that what this machine holds; the machine never outranks the person's own history.
    private func candidates(for query: SuggestionQuery) async -> [Candidate] {
        let remembered =
            (try? await store.candidates(for: query.surface, matching: query.typed)) ?? []
        guard remembered.isEmpty else { return remembered }
        return await environment.candidates(for: query.surface, matching: query.typed, now: Date())
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
        // The question runs a nested event loop, which no turn may sit inside, so it is asked beside the loop.
        Task { await askAboutLearning(from: snapshot) }
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
            selection: session.selection,
            acceptKey: preferences.acceptKeys.key(forBundleIdentifier: snapshot.bundleIdentifier),
            fontFamily: snapshot.fontFamily)
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
                panel.hide()
                interceptor.arm([])
                generating?.cancel()
                // Held across the insert so the keys it posts are ignored on both the tap and the monitor.
                isInserting = true
                await take(text, after: typed, in: reading)
                isInserting = false
                // The field is re-read a moment later, since an application applies the insertion after the keys land.
                wake(.tick, afterMilliseconds: 80)
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

    /// How long the tap rests after macOS disabled it twice, past the window in which disables count against it.
    private static let tapRestSeconds = 90

    /// Rests the tap and starts it again, since a disable is usually the system's doing and the feature need not die of it.
    private func restTap() {
        interceptor.arm([])
        interceptor.stop()
        panel.hide()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.tapRestSeconds))
            guard let self else { return }
            do {
                try interceptor.start()
                Self.log.error("the tap is back after resting \(Self.tapRestSeconds)s")
            } catch {
                Self.log.error("the tap could not restart: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// The one word the log carries for a routed keystroke.
    private static func name(of action: SuggestionAction) -> String {
        switch action {
        case .accept: "accept"
        case .redraw: "redraw"
        case .nothing: "nothing"
        }
    }

    /// Puts the tail into the field and hands the taken line to capture, which weighs it and refuses what it must.
    private func take(_ text: String, after typed: String, in reading: FieldReading?) async {
        do {
            // What the gates left is a whole line, so taking it may replace characters as well as add.
            let method = try await acceptor.accept(.certain(text), after: typed)
            Self.log.debug(
                "ACCEPT text=\(text, privacy: .public) typed=\(typed, privacy: .public) via=\(method?.rawValue ?? "nothing", privacy: .public)"
            )
        } catch {
            // The case names which route refused and why; the user-facing message belongs to dictation, whose route has a clipboard.
            Self.log.error(
                "a completion landed nowhere: \(String(describing: error), privacy: .public) typed=\(typed, privacy: .public)"
            )
            return
        }
        guard let reading else { return }
        _ = try? await capture.accepted(text, in: reading, at: Date())
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
