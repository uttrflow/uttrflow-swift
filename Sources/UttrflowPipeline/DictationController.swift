// Turns key presses and clicks into dictations.
public import UttrflowCore

/// Turns key presses into dictations; generic over the clock so the minimum hold tests instantly.
public actor DictationController<ClockType: Clock> where ClockType.Duration == Duration {
    /// The default hold length: a hold shorter than this is a slip, cancelled rather than reported as too short.
    public static var minimumHold: Duration { .milliseconds(200) }

    /// Two slips closer together than this are one double tap. See Docs/pipeline-gestures.md.
    public static var doubleTapWindow: Duration { .milliseconds(450) }

    /// How long modifiers bound alone must be held before they count, so another shortcut's key can arrive first.
    public static var modifierSettle: Duration { minimumHold }

    /// How long a hold keeps listening after the key comes up, so a slow release keeps the last word. See Docs/audio-capture.md.
    public static var releaseGrace: Duration { .milliseconds(300) }

    private let pipeline: DictationPipeline
    private let monitor: any HotkeyMonitoring
    /// Watches the held command key, whose utterances run as edit commands. See `Docs/commands.md`.
    private let commandMonitor: (any HotkeyMonitoring)?
    /// Sounds the start and a discard; the capture engine sounds the stop, once the microphone has closed.
    private let cue: any RecordingCueing
    private let clock: ClockType
    private let limit: DictationLimit
    /// Told how a long recording is going, so the interface can say so and then stop it.
    private let onAdvice: @Sendable (DictationAdvice) -> Void
    /// Told once when a dictation first reaches its warning point.
    private let onWarning: @Sendable (DictationAdvice) -> Void
    /// Told when the gesture that ends a recording changes, so the dock can say so even mid-recording.
    private let onStopGestureChange: @Sendable (StopGesture) -> Void
    private var limitTask: Task<Void, Never>?
    /// Which dictation's cap `limitTask` is, so an older cap can neither finish nor stop a newer one.
    private var limitGeneration = 0
    /// Ends a recording no key is holding once it falls quiet; nil leaves it to the stop gesture.
    private var endOnSilence: SilenceStop?
    /// Listens for that quiet, under the same generation as the cap.
    private var silenceTask: Task<Void, Never>?
    /// The last finished dictation's recognition and insertion, which run off the queue. See Docs/pipeline-gestures.md.
    private var processing: Task<Void, Never>?

    private var activation: HotkeyActivation
    /// Whether a double tap of held keys leaves the microphone open; off, a short tap is only a slip.
    private var handsFreeEnabled: Bool
    private var doubleTapWindow: Duration
    /// A press shorter than this is a tap; Settings can lengthen it for people who press slowly.
    private var holdLength: Duration
    /// How long the microphone stays open after a hold's key comes up; press-to-toggle and taps have none.
    private let releaseGrace: Duration
    /// Told when a tap lands after the double-tap window but within twice it, so the miss is not silent.
    private let onNearMissTap: @Sendable () -> Void
    private var pressedAt: ClockType.Instant?
    /// When the last slip ended, so the next one can tell whether it is the second of a pair.
    private var lastTapEndedAt: ClockType.Instant?
    /// Whether the microphone was left open by a double tap, and so waits for another to close it.
    private var isHandsFree = false
    /// Whether the active recording began from a control rather than the shortcut.
    private var controlStartedRecording = false
    /// The shortcut being watched, which decides whether a press waits to settle.
    private var binding: HotkeyBinding?
    /// The command key being watched, or nil when none is bound.
    private var commandBinding: HotkeyBinding?
    /// Which key the press in progress, or the last one, came from.
    private var keyRoute: UtteranceRoute = .dictation
    /// A press of modifiers bound alone that has not been held long enough to count yet.
    private var unsettledPress: (id: Int, at: ClockType.Instant)?
    private var nextPressID = 0
    private var settleTask: Task<Void, Never>?
    /// Whether the press in progress opened the microphone, and so what withdrawing it has to undo.
    private var pressOpenedTheMicrophone = false
    /// A key event, or a click that has no release and is told when it has been handled.
    private enum Gesture: Sendable {
        case key(HotkeyEvent, UtteranceRoute)
        case control(DictationCommand, CheckedContinuation<DictationCommandOutcome, Never>)
        /// The press with this id has been held long enough to count.
        case settled(Int)
        /// A new activation mode, answered once adopted.
        case activation(HotkeyActivation, CheckedContinuation<Void, Never>)
        /// Hands-free switched on or off, answered once adopted.
        case handsFree(Bool, CheckedContinuation<Void, Never>)
        /// Answered once everything queued ahead of it has been handled.
        case drained(CheckedContinuation<Void, Never>)
        /// The cap started for this generation of dictation has been reached.
        case limitReached(Int)
        /// This generation of dictation has been quiet for the chosen wait.
        case silenceReached(Int)
        /// The active session is ending, so an open dictation finishes before control leaves the user.
        case sessionEnding(CheckedContinuation<Void, Never>)
        /// Answered once the queue reaches it, whatever is still being processed.
        case reached(CheckedContinuation<Void, Never>)
    }

    /// Every gesture from every source, handled one at a time. See Docs/pipeline-gestures.md.
    private let gestures: AsyncStream<Gesture>
    private let gestureSink: AsyncStream<Gesture>.Continuation

    public init(
        pipeline: DictationPipeline,
        monitor: any HotkeyMonitoring,
        commandMonitor: (any HotkeyMonitoring)? = nil,
        cue: any RecordingCueing = SilentCue(),
        activation: HotkeyActivation = .holdToTalk,
        handsFreeEnabled: Bool = true,
        doubleTapWindow: Duration = .milliseconds(450),
        minimumHold: Duration = .milliseconds(200),
        releaseGrace: Duration = .zero,
        clock: ClockType,
        limit: DictationLimit = .default,
        endOnSilence: SilenceStop? = nil,
        onAdvice: @escaping @Sendable (DictationAdvice) -> Void = { _ in },
        onWarning: @escaping @Sendable (DictationAdvice) -> Void = { _ in },
        onNearMissTap: @escaping @Sendable () -> Void = {},
        onStopGestureChange: @escaping @Sendable (StopGesture) -> Void = { _ in }
    ) {
        self.pipeline = pipeline
        self.monitor = monitor
        self.commandMonitor = commandMonitor
        self.cue = cue
        self.activation = activation
        self.handsFreeEnabled = handsFreeEnabled
        self.doubleTapWindow = doubleTapWindow
        self.holdLength = minimumHold
        self.releaseGrace = releaseGrace
        self.onNearMissTap = onNearMissTap
        self.clock = clock
        self.limit = limit
        self.endOnSilence = endOnSilence
        self.onAdvice = onAdvice
        self.onWarning = onWarning
        self.onStopGestureChange = onStopGestureChange
        (gestures, gestureSink) = AsyncStream<Gesture>.makeStream()
        // Weak, like the forwarder below: a strong `self` here would never let the controller die.
        let queued = gestures
        Task { [weak self] in
            for await gesture in queued {
                guard let self else {
                    // A caller still waiting is answered, so it is not left suspended forever.
                    switch gesture {
                    case .control(_, let handled):
                        handled.resume(returning: .nothingRecording)
                    case .drained(let handled), .reached(let handled),
                        .activation(_, let handled), .handsFree(_, let handled), .sessionEnding(let handled):
                        handled.resume()
                    case .key, .settled, .limitReached, .silenceReached: break
                    }
                    continue
                }
                switch gesture {
                case .key(let event, let route):
                    await respond(to: event, from: route)
                case .control(let command, let handled):
                    let outcome = await perform(command)
                    await answer(handled, with: outcome)
                case .settled(let id):
                    await settle(id)
                case .activation(let activation, let handled):
                    await adopt(activation)
                    await answer(handled)
                case .handsFree(let enabled, let handled):
                    await adoptHandsFree(enabled)
                    await answer(handled)
                case .drained(let handled):
                    await answer(handled)
                case .reached(let handled):
                    handled.resume()
                case .limitReached(let generation):
                    await finishAtTheLimit(generation)
                case .silenceReached(let generation):
                    await finishOnSilence(generation)
                case .sessionEnding(let handled):
                    await finishForSessionEnding()
                    await answer(handled)
                }
            }
        }
        // Forwarded once for the controller's life: an `AsyncStream` has room for one reader.
        let events = monitor.events
        Task { [weak self] in
            for await event in events { self?.submit(event) }
        }
        if let commandEvents = commandMonitor?.events {
            Task { [weak self] in
                for await event in commandEvents { self?.submit(event, from: .command) }
            }
        }
        // Tells the dock the resting gesture so a press-to-toggle shortcut does not read .letGo.
        onStopGestureChange(Self.currentStopGesture(activation: activation, isHandsFree: false))
    }

    deinit {
        // Ends the gesture task, which is waiting on a stream only this controller can finish.
        gestureSink.finish()
    }

    /// Queues a gesture from any source behind whatever is in flight, and returns at once.
    public nonisolated func submit(_ event: HotkeyEvent, from route: UtteranceRoute = .dictation) {
        gestureSink.yield(.key(event, route))
    }

    /// Watches for the shortcut, or rebinds to another one. See Docs/pipeline-gestures.md.
    public func start(binding: HotkeyBinding) async throws(HotkeyError) {
        await abandonUnsettledPress()
        self.binding = binding
        try await monitor.start(binding: binding)
    }

    /// Watches for the command key, or stops watching when it is nil; separate so a refusal leaves dictation armed.
    public func start(commandBinding: HotkeyBinding?) async throws(HotkeyError) {
        guard let commandMonitor else { return }
        await abandonUnsettledPress()
        self.commandBinding = commandBinding
        guard let commandBinding else { return commandMonitor.stop() }
        try await commandMonitor.start(binding: commandBinding)
    }

    /// Stops watching for the shortcut, first finishing any dictation under way so no microphone outlives it.
    public func stop() async {
        await endForSessionEnding()
        await abandonUnsettledPress()
        stopWatchingTheLimit()
        // Stopped last, so the release it owes for a hold still reaches the forwarder.
        monitor.stop()
        commandMonitor?.stop()
    }

    /// Changes the mode, queued behind every gesture, finishing any dictation under way. See Docs/pipeline-gestures.md.
    public nonisolated func setActivation(_ activation: HotkeyActivation) async {
        await withCheckedContinuation { handled in
            // A controller already gone has no queue, so the change is answered at once.
            guard case .enqueued = gestureSink.yield(.activation(activation, handled)) else {
                handled.resume()
                return
            }
        }
    }

    /// Adopts a new mode, ending what the old one started so no microphone outlives the rules that opened it.
    private func adopt(_ activation: HotkeyActivation) async {
        guard activation != self.activation else { return }
        self.activation = activation
        await abandonUnsettledPress()
        pressedAt = nil
        lastTapEndedAt = nil
        pressOpenedTheMicrophone = false
        isHandsFree = false
        onStopGestureChange(currentStopGesture)
        guard await pipeline.currentState.isListening else { return }
        stopWatchingTheLimit()
        await finishListening()
    }

    public var currentActivation: HotkeyActivation { activation }

    /// Switches the double tap on or off, queued behind every gesture. See Docs/pipeline-gestures.md.
    public nonisolated func setHandsFreeEnabled(_ enabled: Bool) async {
        await withCheckedContinuation { handled in
            // A controller already gone has no queue, so the change is answered at once.
            guard case .enqueued = gestureSink.yield(.handsFree(enabled, handled)) else {
                handled.resume()
                return
            }
        }
    }

    /// Adopts the switch, closing a microphone a double tap left open once the gesture is off.
    private func adoptHandsFree(_ enabled: Bool) async {
        guard enabled != handsFreeEnabled else { return }
        handsFreeEnabled = enabled
        lastTapEndedAt = nil
        guard !enabled else { return }
        await forgetHandsFreeIfEnded()
        guard isHandsFree else { return }
        await stopHandsFree()
    }

    public var isHandsFreeEnabled: Bool { handsFreeEnabled }

    /// Changes how far apart hands-free taps may be.
    public func setDoubleTapWindow(_ window: Duration) {
        doubleTapWindow = window
    }

    /// Changes the quiet that ends a recording no key is holding, from the next dictation on.
    public func setEndOnSilence(_ stop: SilenceStop?) {
        endOnSilence = stop
    }

    /// Changes how long a press may last and still count as a tap.
    public func setMinimumHold(_ hold: Duration) {
        holdLength = hold
    }

    /// Records a tap that did not pair, announcing it when it fell just outside the window.
    private func recordUnpairedTap(at now: ClockType.Instant) {
        if handsFreeEnabled, let last = lastTapEndedAt, last.duration(to: now) < doubleTapWindow * 2 {
            onNearMissTap()
        }
        lastTapEndedAt = now
    }

    /// What the dock has to say to end a recording that is under way right now.
    public var currentStopGesture: StopGesture {
        if controlStartedRecording { return .clickAgain }
        return Self.currentStopGesture(activation: activation, isHandsFree: isHandsFree)
    }

    /// Pure form of ``currentStopGesture``, callable from any context.
    static func currentStopGesture(activation: HotkeyActivation, isHandsFree: Bool) -> StopGesture {
        switch (activation, isHandsFree) {
        case (.holdToTalk, false): .letGo
        case (.holdToTalk, true): .pressAgainHandsFree
        case (.pressToToggle, _): .pressAgain
        }
    }

    /// Sets the hands-free flag and tells the dock when the gesture that ends the recording has changed.
    private func setHandsFree(_ value: Bool) {
        guard isHandsFree != value else { return }
        isHandsFree = value
        onStopGestureChange(currentStopGesture)
    }

    /// Answers a waiting caller once any dictation finished so far has been inserted, without holding the queue.
    private func answer(_ handled: CheckedContinuation<Void, Never>) {
        answer(handled, with: ())
    }

    private func answer<Outcome: Sendable>(
        _ handled: CheckedContinuation<Outcome, Never>, with outcome: Outcome
    ) {
        guard let processing else { return handled.resume(returning: outcome) }
        Task {
            await processing.value
            handled.resume(returning: outcome)
        }
    }

    /// Closes the microphone and leaves recognition and insertion to run while the next gesture is handled.
    private func finishListening() async {
        guard let started = await pipeline.stopListening() else { return }
        processing = started
        resetControlStartedRecording()
    }

    /// Returns the dock to the shortcut's gesture after a control-started recording ends.
    private func resetControlStartedRecording() {
        guard controlStartedRecording else { return }
        controlStartedRecording = false
        onStopGestureChange(currentStopGesture)
    }

    // MARK: Events

    /// Handles one event and returns once any dictation it finished has been inserted.
    public func handle(_ event: HotkeyEvent, from route: UtteranceRoute = .dictation) async {
        await respond(to: event, from: route)
        await processing?.value
    }

    /// Handles one event, returning as soon as the microphone is closed.
    private func respond(to event: HotkeyEvent, from route: UtteranceRoute) async {
        if case .escapePressed = event {
            await cancelListening()
            return
        }
        guard await admits(event, from: route) else { return }
        if let unsettled = unsettledPress {
            await resolveUnsettledPress(unsettled, with: event)
            return
        }
        switch (activation, event) {
        case (_, .pressed) where waitsToSettle:
            await holdBack()

        case (_, .pressed):
            await press(at: clock.now)

        case (.holdToTalk, .released):
            await endHold()

        // Releasing does nothing in toggle mode: the next press is what stops it.
        case (.pressToToggle, .released):
            break

        case (_, .cancelled):
            await withdrawPress()

        case (_, .escapePressed):
            await cancelListening()

        }
    }

    /// Discards the dictation under way when Escape is pressed, whether still listening or already being processed.
    private func cancelListening() async {
        await abandonUnsettledPress()
        pressedAt = nil
        lastTapEndedAt = nil
        pressOpenedTheMicrophone = false
        setHandsFree(false)
        guard await pipeline.currentState.isBusy else { return }
        stopWatchingTheLimit()
        await abandon()
        resetControlStartedRecording()
    }

    /// Cancels the dictation, sounding the discarded cue when the pipeline says the cancel cost a long take.
    private func abandon() async {
        await pipeline.cancel()
        if case .discarded = await pipeline.currentState { cue.playDiscarded() }
    }

    /// Whether an event belongs to the key in use; the other key's press takes over only once nothing is under way.
    private func admits(_ event: HotkeyEvent, from route: UtteranceRoute) async -> Bool {
        guard route != keyRoute else { return true }
        guard event == .pressed, unsettledPress == nil, pressedAt == nil, !isHandsFree,
            !(await pipeline.currentState.isListening)
        else { return false }
        keyRoute = route
        lastTapEndedAt = nil
        return true
    }

    /// Whether a press waits to settle, which modifier holds use before they can start dictation.
    private var waitsToSettle: Bool {
        guard let held = keyRoute == .command ? commandBinding : binding else { return false }
        return held.heldModifier != nil
    }

    /// Acts on a press once it counts, measured from when the keys went down.
    private func press(at instant: ClockType.Instant, modifierCaptureIsOpen: Bool = false) async {
        switch activation {
        case .holdToTalk:
            pressedAt = instant
            await forgetHandsFreeIfEnded()
            // Hands-free is already listening; pressing again is the start of the gesture that ends it.
            guard !isHandsFree else {
                pressOpenedTheMicrophone = false
                return
            }
            // A click already opened the microphone, so this press does not own the recording.
            if await pipeline.currentState.isListening {
                pressOpenedTheMicrophone = false
                return
            }
            await beginListening(route: keyRoute, adoptingModifierCapture: modifierCaptureIsOpen)
            pressOpenedTheMicrophone = await pipeline.currentState.isListening
        case .pressToToggle:
            let wasListening = await pipeline.currentState.isListening
            // The settled press's key-down microphone is the recording; the pipeline refuses a second one beside it.
            if modifierCaptureIsOpen, !wasListening {
                await beginListening(route: keyRoute, adoptingModifierCapture: true)
            } else {
                _ = await perform(.toggle, route: keyRoute, fromControl: false)
            }
            let isListening = await pipeline.currentState.isListening
            pressOpenedTheMicrophone = !wasListening && isListening
        }
    }

    /// Waits out the settle before a press of modifiers alone counts. See `Docs/shortcuts.md`.
    private func holdBack() async {
        nextPressID += 1
        let id = nextPressID
        let pressedAt = clock.now
        unsettledPress = (id, pressedAt)
        let elapsed = UttrflowCore.stopwatch(from: clock)
        await pipeline.beginModifierPress(measuring: elapsed)
        let deadline = pressedAt.advanced(by: Self.modifierSettle)
        settleTask = Task { [clock, gestureSink] in
            do {
                try await clock.sleep(until: deadline, tolerance: nil)
            } catch {
                // Cancelled, because the press was released or withdrawn before it settled.
                return
            }
            gestureSink.yield(.settled(id))
        }
    }

    /// Makes the press count, unless it was released or withdrawn while it waited.
    private func settle(_ id: Int) async {
        guard let unsettled = unsettledPress, unsettled.id == id else { return }
        forgetUnsettledPress()
        await press(at: unsettled.at, modifierCaptureIsOpen: true)
    }

    /// A release or withdrawal that arrived before the press settled.
    private func resolveUnsettledPress(
        _ unsettled: (id: Int, at: ClockType.Instant), with event: HotkeyEvent
    ) async {
        switch (activation, event) {
        // Another press cannot arrive before a release, so a repeat is only a duplicate.
        case (_, .pressed):
            return
        case (_, .cancelled):
            forgetUnsettledPress()
            await pipeline.cancelModifierPress()
        case (.holdToTalk, .released):
            forgetUnsettledPress()
            if unsettled.at.duration(to: clock.now) < holdLength {
                await pipeline.cancelModifierPress()
                await endTapThatNeverOpened()
            } else {
                await press(at: unsettled.at, modifierCaptureIsOpen: true)
                await endHold()
            }
        case (.pressToToggle, .released):
            forgetUnsettledPress()
            await press(at: unsettled.at, modifierCaptureIsOpen: true)

        case (_, .escapePressed):
            forgetUnsettledPress()
            await cancelListening()
        }
    }

    /// Forgets a waiting press and closes the microphone it opened on key-down, so none outlives a rebind, stop or mode change.
    private func abandonUnsettledPress() async {
        guard unsettledPress != nil else { return }
        forgetUnsettledPress()
        await pipeline.cancelModifierPress()
    }

    private func forgetUnsettledPress() {
        settleTask?.cancel()
        settleTask = nil
        unsettledPress = nil
    }

    /// Undoes what a press opened, without inserting anything, because its keys began another shortcut.
    private func withdrawPress() async {
        pressedAt = nil
        guard pressOpenedTheMicrophone else { return }
        pressOpenedTheMicrophone = false
        guard await pipeline.currentState.isListening, !isHandsFree else { return }
        stopWatchingTheLimit()
        await abandon()
    }

    /// Suspends until a waiting press has settled or been forgotten, which only the clock can decide.
    func settling() async {
        await settleTask?.value
    }

    /// Suspends until every gesture queued so far has been handled.
    func drained() async {
        await withCheckedContinuation { handled in
            guard case .enqueued = gestureSink.yield(.drained(handled)) else {
                handled.resume()
                return
            }
        }
    }

    /// Suspends until every gesture queued so far has been handled, without waiting for insertion.
    func caughtUp() async {
        await withCheckedContinuation { handled in
            guard case .enqueued = gestureSink.yield(.reached(handled)) else {
                handled.resume()
                return
            }
        }
    }

    /// Toggles a dictation from a click, queued behind every other gesture; returns once handled. See Docs/pipeline-gestures.md.
    public nonisolated func toggleFromControl() async {
        _ = await command(.toggle)
    }

    /// Runs one command from a click or a spoken intent, queued behind every other gesture, and says what it did.
    public nonisolated func command(_ command: DictationCommand) async -> DictationCommandOutcome {
        await withCheckedContinuation { handled in
            // A controller already gone has no queue, so the command is answered at once.
            guard case .enqueued = gestureSink.yield(.control(command, handled)) else {
                handled.resume(returning: .nothingRecording)
                return
            }
        }
    }

    /// Queues the normal stop path for sleep, lock, or a user switch.
    public nonisolated func endForSessionEnding() async {
        await withCheckedContinuation { handled in
            guard case .enqueued = gestureSink.yield(.sessionEnding(handled)) else {
                handled.resume()
                return
            }
        }
    }

    private func finishForSessionEnding() async {
        guard await pipeline.currentState.isListening else { return }
        forgetUnsettledPress()
        pressedAt = nil
        lastTapEndedAt = nil
        pressOpenedTheMicrophone = false
        setHandsFree(false)
        stopWatchingTheLimit()
        await finishListening()
    }

    /// Carries out a command against the state the queue finds, so a spoken command cannot act on a stale guess.
    private func perform(
        _ command: DictationCommand, route: UtteranceRoute = .dictation, fromControl: Bool = true
    ) async -> DictationCommandOutcome {
        let listening = await pipeline.currentState.isListening
        switch (command, listening) {
        case (.toggle, true), (.stop, true):
            setHandsFree(false)
            stopWatchingTheLimit()
            await finishListening()
            return .finished
        case (.toggle, false), (.start, false):
            await beginListening(route: route)
            guard await pipeline.currentState.isListening else { return .didNotStart }
            // Only a control is ended by a click; the press-to-toggle shortcut ends its own recording.
            guard fromControl else { return .started }
            controlStartedRecording = true
            onStopGestureChange(.clickAgain)
            return .started
        case (.start, true):
            return .alreadyRecording
        case (.cancel, _):
            guard await pipeline.currentState.isBusy else { return .nothingRecording }
            await cancelListening()
            return .cancelled
        case (.stop, false):
            return .nothingRecording
        }
    }

    private func beginListening(route: UtteranceRoute, adoptingModifierCapture: Bool = false) async {
        resetControlStartedRecording()
        // The previous take can still be transcribed; a new capture must not wait for its insertion.
        if let processing {
            self.processing = nil
            Task { await processing.value }
        }
        await pipeline.route(next: route)
        if adoptingModifierCapture {
            await pipeline.adoptModifierPress()
        } else {
            await pipeline.startRecording()
        }
        // Only once the pipeline is listening, so a refused microphone does not sound as though it worked.
        if await pipeline.currentState.isListening {
            cue.playStart()
            watchTheLimit()
        }
    }

    /// Warns before the cap and queues its finish like any gesture, keeping the words. See `Docs/stuck-recording.md`.
    private func watchTheLimit() {
        limitTask?.cancel()
        limitGeneration += 1
        let generation = limitGeneration
        limitTask = Task { [clock, limit, onAdvice, onWarning, gestureSink] in
            let start = clock.now
            do {
                // Deadlines from the start, so a late wake-up cannot push the cap back.
                for elapsed in limit.countdown {
                    try await clock.sleep(until: start.advanced(by: elapsed), tolerance: nil)
                    if elapsed == limit.warnAfter {
                        onWarning(limit.advice(at: elapsed))
                    }
                    onAdvice(limit.advice(at: elapsed))
                }
                try await clock.sleep(until: start.advanced(by: limit.stopAfter), tolerance: nil)
            } catch {
                // Cancelled, which is the ordinary end of every dictation.
                return
            }
            gestureSink.yield(.limitReached(generation))
        }
        silenceTask = endOnSilence.map { stop in
            Task { [pipeline, clock, gestureSink] in
                do { try await pipeline.silence(reaching: stop, on: clock) } catch { return }
                gestureSink.yield(.silenceReached(generation))
            }
        }
    }

    /// Ends a recording that fell quiet the way its stop gesture would; one a key still holds is left to the key.
    private func finishOnSilence(_ generation: Int) async {
        guard generation == limitGeneration, silenceTask != nil, currentStopGesture != .letGo,
            await pipeline.currentState.isListening
        else { return }
        setHandsFree(false)
        stopWatchingTheLimit()
        await finishListening()
    }

    /// Ends a dictation that reached its own cap, keeping every word of it; a stale cap does nothing.
    private func finishAtTheLimit(_ generation: Int) async {
        guard generation == limitGeneration, limitTask != nil else { return }
        onAdvice(.finishNow)
        guard await pipeline.currentState.isListening else { return stopWatchingTheLimit(generation) }
        setHandsFree(false)
        await finishListening()
        stopWatchingTheLimit(generation)
    }

    /// Stops the cap of the given generation only, so a late call cannot stop the next dictation's.
    private func stopWatchingTheLimit(_ generation: Int) {
        guard generation == limitGeneration else { return }
        stopWatchingTheLimit()
    }

    private func stopWatchingTheLimit() {
        limitTask?.cancel()
        limitTask = nil
        silenceTask?.cancel()
        silenceTask = nil
        onAdvice(.keepGoing)
    }

    private func endHold() async {
        let pressed = pressedAt
        defer { pressedAt = nil }
        guard await pipeline.currentState.isListening else { return }

        let now = clock.now
        let wasTap = pressed.map { $0.duration(to: now) < holdLength } ?? false
        if wasTap, handsFreeEnabled, let last = lastTapEndedAt,
            last.duration(to: now) < doubleTapWindow
        {
            // A press that did not open the microphone and was not part of a hands-free toggle cannot change the gesture a click-started dictation is waiting for.
            guard pressOpenedTheMicrophone || isHandsFree else { return }
            lastTapEndedAt = nil
            if isHandsFree { await stopHandsFree() } else { setHandsFree(true) }
            return
        }
        if wasTap {
            recordUnpairedTap(at: now)
            // A single tap while hands-free changes nothing; it may yet be half of the pair that ends it.
            guard !isHandsFree else { return }
            // A slip on a click-started dictation finishes it cleanly, the way a release would, rather than discarding the words.
            guard pressOpenedTheMicrophone else {
                stopWatchingTheLimit()
                await finishListening()
                return
            }
            stopWatchingTheLimit()
            await abandon()
            return
        }
        // A real hold, so any earlier tap is no longer waiting to pair with the next one.
        lastTapEndedAt = nil
        // Letting go of a key that was never held is what ends a hold, and hands-free has no hold.
        guard !isHandsFree else { return }
        stopWatchingTheLimit()
        if releaseGrace > .zero { try? await clock.sleep(for: releaseGrace) }
        await finishListening()
    }

    /// A tap too short to settle, counted towards a double tap without opening the microphone for one.
    private func endTapThatNeverOpened() async {
        guard handsFreeEnabled else { return }
        let now = clock.now
        guard let last = lastTapEndedAt, last.duration(to: now) < doubleTapWindow else {
            recordUnpairedTap(at: now)
            return
        }
        lastTapEndedAt = nil
        await forgetHandsFreeIfEnded()
        guard !isHandsFree else { return await stopHandsFree() }
        await beginListening(route: keyRoute)
        setHandsFree(await pipeline.currentState.isListening)
    }

    /// Forgets hands-free once its dictation has ended some other way, so the next hold and double tap work.
    private func forgetHandsFreeIfEnded() async {
        guard isHandsFree, !(await pipeline.currentState.isListening) else { return }
        setHandsFree(false)
    }

    /// Closes a microphone a double tap left open, as the second double tap does.
    private func stopHandsFree() async {
        setHandsFree(false)
        stopWatchingTheLimit()
        await finishListening()
    }
}
