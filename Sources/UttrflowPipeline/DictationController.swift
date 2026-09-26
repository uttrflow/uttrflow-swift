// Turns key presses and clicks into dictations.
public import UttrflowCore

/// Turns key presses into dictations; generic over the clock so the minimum hold tests instantly.
public actor DictationController<ClockType: Clock> where ClockType.Duration == Duration {
    /// A hold shorter than this is a slip, cancelled silently rather than reported as too short.
    public static var minimumHold: Duration { .milliseconds(200) }

    /// Two slips closer together than this are one double tap. See Docs/pipeline-gestures.md.
    public static var doubleTapWindow: Duration { .milliseconds(450) }

    /// How long modifiers bound alone must be held before they count, so another shortcut's key can arrive first.
    public static var modifierSettle: Duration { minimumHold }

    private let pipeline: DictationPipeline
    private let monitor: any HotkeyMonitoring
    /// Sounds the start only; the capture engine sounds the stop, once the microphone has closed.
    private let cue: any RecordingCueing
    private let clock: ClockType
    private let limit: DictationLimit
    /// Told how a long recording is going, so the interface can say so and then stop it.
    private let onAdvice: @Sendable (DictationAdvice) -> Void
    /// Told when the gesture that ends a recording changes, so the dock can say so even mid-recording.
    private let onStopGestureChange: @Sendable (StopGesture) -> Void
    private var limitTask: Task<Void, Never>?
    /// Which dictation's cap `limitTask` is, so an older cap can neither finish nor stop a newer one.
    private var limitGeneration = 0

    private var activation: HotkeyActivation
    private var pressedAt: ClockType.Instant?
    /// When the last slip ended, so the next one can tell whether it is the second of a pair.
    private var lastTapEndedAt: ClockType.Instant?
    /// Whether the microphone was left open by a double tap, and so waits for another to close it.
    private var isHandsFree = false
    /// The shortcut being watched, which decides whether a press waits to settle.
    private var binding: HotkeyBinding?
    /// A press of modifiers bound alone that has not been held long enough to count yet.
    private var unsettledPress: (id: Int, at: ClockType.Instant)?
    private var nextPressID = 0
    private var settleTask: Task<Void, Never>?
    /// Whether the press in progress opened the microphone, and so what withdrawing it has to undo.
    private var pressOpenedTheMicrophone = false
    /// A key event, or a click that has no release and is told when it has been handled.
    private enum Gesture: Sendable {
        case key(HotkeyEvent)
        case control(CheckedContinuation<Void, Never>)
        /// The press with this id has been held long enough to count.
        case settled(Int)
        /// A new activation mode, answered once adopted.
        case activation(HotkeyActivation, CheckedContinuation<Void, Never>)
        /// Answered once everything queued ahead of it has been handled.
        case drained(CheckedContinuation<Void, Never>)
        /// The cap started for this generation of dictation has been reached.
        case limitReached(Int)
    }

    /// Every gesture from every source, handled one at a time. See Docs/pipeline-gestures.md.
    private let gestures: AsyncStream<Gesture>
    private let gestureSink: AsyncStream<Gesture>.Continuation

    public init(
        pipeline: DictationPipeline,
        monitor: any HotkeyMonitoring,
        cue: any RecordingCueing = SilentCue(),
        activation: HotkeyActivation = .holdToTalk,
        clock: ClockType,
        limit: DictationLimit = .default,
        onAdvice: @escaping @Sendable (DictationAdvice) -> Void = { _ in },
        onStopGestureChange: @escaping @Sendable (StopGesture) -> Void = { _ in }
    ) {
        self.pipeline = pipeline
        self.monitor = monitor
        self.cue = cue
        self.activation = activation
        self.clock = clock
        self.limit = limit
        self.onAdvice = onAdvice
        self.onStopGestureChange = onStopGestureChange
        (gestures, gestureSink) = AsyncStream<Gesture>.makeStream()
        // Weak, like the forwarder below: a strong `self` here would never let the controller die.
        let queued = gestures
        Task { [weak self] in
            for await gesture in queued {
                guard let self else {
                    // A caller still waiting is answered, so it is not left suspended forever.
                    switch gesture {
                    case .control(let handled), .drained(let handled), .activation(_, let handled):
                        handled.resume()
                    case .key, .settled, .limitReached: break
                    }
                    continue
                }
                switch gesture {
                case .key(let event):
                    await handle(event)
                case .control(let handled):
                    await toggleListening()
                    handled.resume()
                case .settled(let id):
                    await settle(id)
                case .activation(let activation, let handled):
                    await adopt(activation)
                    handled.resume()
                case .drained(let handled):
                    handled.resume()
                case .limitReached(let generation):
                    await finishAtTheLimit(generation)
                }
            }
        }
        // Forwarded once for the controller's life: an `AsyncStream` has room for one reader.
        let events = monitor.events
        Task { [weak self] in
            for await event in events { self?.submit(event) }
        }
        // Tells the dock the resting gesture so a press-to-toggle shortcut does not read .letGo.
        onStopGestureChange(Self.currentStopGesture(activation: activation, isHandsFree: false))
    }

    deinit {
        // Ends the gesture task, which is waiting on a stream only this controller can finish.
        gestureSink.finish()
    }

    /// Queues a gesture from any source behind whatever is in flight, and returns at once.
    public nonisolated func submit(_ event: HotkeyEvent) {
        gestureSink.yield(.key(event))
    }

    /// Watches for the shortcut, or rebinds to another one. See Docs/pipeline-gestures.md.
    public func start(binding: HotkeyBinding) async throws(HotkeyError) {
        forgetUnsettledPress()
        self.binding = binding
        try await monitor.start(binding: binding)
    }

    public func stop() {
        forgetUnsettledPress()
        stopWatchingTheLimit()
        // Stopped last, so the release it owes for a hold still reaches the forwarder.
        monitor.stop()
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
        forgetUnsettledPress()
        pressedAt = nil
        lastTapEndedAt = nil
        pressOpenedTheMicrophone = false
        isHandsFree = false
        onStopGestureChange(currentStopGesture)
        guard await pipeline.currentState.isListening else { return }
        stopWatchingTheLimit()
        await pipeline.finishRecording()
    }

    public var currentActivation: HotkeyActivation { activation }

    /// What the dock has to say to end a recording that is under way right now.
    public var currentStopGesture: StopGesture {
        Self.currentStopGesture(activation: activation, isHandsFree: isHandsFree)
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

    // MARK: Events

    public func handle(_ event: HotkeyEvent) async {
        if let unsettled = unsettledPress {
            await resolveUnsettledPress(unsettled, with: event)
            return
        }
        switch (activation, event) {
        case (_, .pressed) where waitsToSettle:
            holdBack()

        case (_, .pressed):
            await press(at: clock.now)

        case (.holdToTalk, .released):
            await endHold()

        // Releasing does nothing in toggle mode: the next press is what stops it.
        case (.pressToToggle, .released):
            break

        case (_, .cancelled):
            await withdrawPress()
        }
    }

    /// Whether a press waits to settle, which only modifiers bound alone do; Fn is read from its own flag.
    private var waitsToSettle: Bool {
        guard let binding else { return false }
        return binding.heldModifier != nil && !binding.isFunctionHold
    }

    /// Acts on a press once it counts, measured from when the keys went down.
    private func press(at instant: ClockType.Instant) async {
        switch activation {
        case .holdToTalk:
            pressedAt = instant
            await forgetHandsFreeIfEnded()
            // Hands-free is already listening; pressing again is the start of the gesture that ends it.
            guard !isHandsFree else {
                pressOpenedTheMicrophone = false
                return
            }
            await beginListening()
            pressOpenedTheMicrophone = await pipeline.currentState.isListening
        case .pressToToggle:
            let wasListening = await pipeline.currentState.isListening
            await toggleListening()
            let isListening = await pipeline.currentState.isListening
            pressOpenedTheMicrophone = !wasListening && isListening
        }
    }

    /// Waits out the settle before a press of modifiers alone counts. See `Docs/shortcuts.md`.
    private func holdBack() {
        nextPressID += 1
        let id = nextPressID
        let pressedAt = clock.now
        unsettledPress = (id, pressedAt)
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
        await press(at: unsettled.at)
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
        case (.holdToTalk, .released):
            forgetUnsettledPress()
            await endTapThatNeverOpened()
        case (.pressToToggle, .released):
            forgetUnsettledPress()
            await press(at: unsettled.at)
        }
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
        await pipeline.cancel()
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

    /// Toggles a dictation from a click, queued behind every other gesture; returns once handled. See Docs/pipeline-gestures.md.
    public nonisolated func toggleFromControl() async {
        await withCheckedContinuation { handled in
            // A controller already gone has no queue, so the click is answered at once.
            guard case .enqueued = gestureSink.yield(.control(handled)) else {
                handled.resume()
                return
            }
        }
    }

    /// Finishes the dictation under way, or begins one.
    private func toggleListening() async {
        if await pipeline.currentState.isListening {
            setHandsFree(false)
            stopWatchingTheLimit()
            await pipeline.finishRecording()
        } else {
            await beginListening()
        }
    }

    private func beginListening() async {
        await pipeline.startRecording()
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
        limitTask = Task { [clock, limit, onAdvice, gestureSink] in
            let start = clock.now
            do {
                // Deadlines from the start, so a late wake-up cannot push the cap back.
                for elapsed in limit.countdown {
                    try await clock.sleep(until: start.advanced(by: elapsed), tolerance: nil)
                    onAdvice(limit.advice(at: elapsed))
                }
                try await clock.sleep(until: start.advanced(by: limit.stopAfter), tolerance: nil)
            } catch {
                // Cancelled, which is the ordinary end of every dictation.
                return
            }
            gestureSink.yield(.limitReached(generation))
        }
    }

    /// Ends a dictation that reached its own cap, keeping every word of it; a stale cap does nothing.
    private func finishAtTheLimit(_ generation: Int) async {
        guard generation == limitGeneration, limitTask != nil else { return }
        onAdvice(.finishNow)
        guard await pipeline.currentState.isListening else { return stopWatchingTheLimit(generation) }
        setHandsFree(false)
        await pipeline.finishRecording()
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
        onAdvice(.keepGoing)
    }

    private func endHold() async {
        let pressed = pressedAt
        defer { pressedAt = nil }
        guard await pipeline.currentState.isListening else { return }

        let now = clock.now
        let wasTap = pressed.map { $0.duration(to: now) < Self.minimumHold } ?? false
        if wasTap, let last = lastTapEndedAt, last.duration(to: now) < Self.doubleTapWindow {
            lastTapEndedAt = nil
            if isHandsFree { await stopHandsFree() } else { setHandsFree(true) }
            return
        }
        if wasTap {
            lastTapEndedAt = now
            // A single tap while hands-free changes nothing; it may yet be half of the pair that ends it.
            guard !isHandsFree else { return }
            stopWatchingTheLimit()
            await pipeline.cancel()
            return
        }
        // A real hold, so any earlier tap is no longer waiting to pair with the next one.
        lastTapEndedAt = nil
        // Letting go of a key that was never held is what ends a hold, and hands-free has no hold.
        guard !isHandsFree else { return }
        stopWatchingTheLimit()
        await pipeline.finishRecording()
    }

    /// A tap too short to settle, counted towards a double tap without opening the microphone for one.
    private func endTapThatNeverOpened() async {
        let now = clock.now
        guard let last = lastTapEndedAt, last.duration(to: now) < Self.doubleTapWindow else {
            lastTapEndedAt = now
            return
        }
        lastTapEndedAt = nil
        await forgetHandsFreeIfEnded()
        guard !isHandsFree else { return await stopHandsFree() }
        await beginListening()
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
        await pipeline.finishRecording()
    }
}
