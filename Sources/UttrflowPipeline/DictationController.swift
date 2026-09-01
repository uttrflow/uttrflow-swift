public import UttrflowCore

/// Turns key presses into dictations.
///
/// The two activation modes differ only here, which is why neither the hotkey monitor
/// below nor the pipeline above knows there is more than one way to start.
///
/// Generic over the clock so that the minimum-hold rule can be tested exactly and
/// instantly, rather than by sleeping.
public actor DictationController<ClockType: Clock> where ClockType.Duration == Duration {
    /// A hold shorter than this was a slip, not a dictation.
    ///
    /// Tapping the shortcut by accident would otherwise start and instantly stop a
    /// recording, and the user would be told their speech was too short to transcribe —
    /// an error for something they never meant to do. Cancelling silently is the honest
    /// response to a slip.
    public static var minimumHold: Duration { .milliseconds(200) }

    private let pipeline: DictationPipeline
    private let monitor: any HotkeyMonitoring
    private let cue: any RecordingCueing
    private let clock: ClockType
    private let limit: DictationLimit
    /// Told how a long recording is going, so the interface can say so and then stop it.
    private let onAdvice: @Sendable (DictationAdvice) -> Void
    private var limitTask: Task<Void, Never>?

    private var activation: HotkeyActivation
    private var pressedAt: ClockType.Instant?
    private var eventTask: Task<Void, Never>?
    private var forwardingTask: Task<Void, Never>?

    /// Every gesture arrives here, from whatever source, and is handled one at a time.
    ///
    /// This has to exist because ``handle(_:)`` suspends: it awaits the pipeline while
    /// the microphone opens. An actor is reentrant across that suspension, so a press
    /// and a release delivered as two independent tasks can interleave — the release
    /// runs first, sees a pipeline that is not listening yet, and returns. The press
    /// then completes and the recording is left running with nothing able to stop it.
    ///
    /// The shortcut never hit this because its events already arrive down one sequential
    /// stream. The floating button did, and on first launch it hit it every time: the
    /// microphone prompt makes `start()` take seconds, so the release always lost.
    private let gestures: AsyncStream<HotkeyEvent>
    private let gestureSink: AsyncStream<HotkeyEvent>.Continuation

    public init(
        pipeline: DictationPipeline,
        monitor: any HotkeyMonitoring,
        cue: any RecordingCueing = SilentCue(),
        activation: HotkeyActivation = .holdToTalk,
        clock: ClockType,
        limit: DictationLimit = .default,
        onAdvice: @escaping @Sendable (DictationAdvice) -> Void = { _ in }
    ) {
        self.pipeline = pipeline
        self.monitor = monitor
        self.cue = cue
        self.activation = activation
        self.clock = clock
        self.limit = limit
        self.onAdvice = onAdvice
        (gestures, gestureSink) = AsyncStream<HotkeyEvent>.makeStream()
        Task { await self.consumeGestures() }
    }

    /// Hands a gesture to the controller from anywhere — the shortcut, the floating
    /// button, a menu item. Returns immediately; the work is queued behind whatever is
    /// already in flight.
    public nonisolated func submit(_ event: HotkeyEvent) {
        gestureSink.yield(event)
    }

    private func consumeGestures() async {
        for await event in gestures {
            await handle(event)
        }
    }

    /// Begins watching for the shortcut, or rebinds to a different one.
    ///
    /// Called again whenever the user changes the shortcut, so the previous forwarding
    /// task has to go first. The monitor's `events` is one stream for the life of the
    /// monitor: leaving the old task iterating it would leave two consumers on one
    /// `AsyncStream`, and each keypress would go to whichever happened to be waiting —
    /// so roughly every other press would vanish.
    public func start(binding: HotkeyBinding) async throws(HotkeyError) {
        forwardingTask?.cancel()
        forwardingTask = nil

        try await monitor.start(binding: binding)
        // Forwarded rather than handled here, so the shortcut queues behind the same
        // single consumer as every other source.
        let events = monitor.events
        forwardingTask = Task { [weak self] in
            for await event in events {
                self?.submit(event)
            }
        }
    }

    public func stop() {
        forwardingTask?.cancel()
        forwardingTask = nil
        eventTask?.cancel()
        eventTask = nil
        stopWatchingTheLimit()
        monitor.stop()
    }

    public func setActivation(_ activation: HotkeyActivation) {
        self.activation = activation
    }

    public var currentActivation: HotkeyActivation { activation }

    // MARK: Events

    public func handle(_ event: HotkeyEvent) async {
        switch (activation, event) {
        case (.holdToTalk, .pressed):
            pressedAt = clock.now
            await beginListening()

        case (.holdToTalk, .released):
            await endHold()

        case (.pressToToggle, .pressed):
            if await pipeline.currentState.isListening {
                stopWatchingTheLimit()
                cue.playStop()
                await pipeline.finishRecording()
            } else {
                await beginListening()
            }

        // Releasing does nothing in toggle mode: the next press is what stops it.
        case (.pressToToggle, .released):
            break
        }
    }

    /// Starts or stops a dictation from a control somebody clicked, rather than a key
    /// they are holding.
    ///
    /// A click has no release, and both ways of pretending otherwise were broken. Sending
    /// `.pressed` and `.released` together made a hold shorter than the slip threshold, so
    /// the recording was cancelled the instant it began — or, when the microphone was slow
    /// to open, ran a whole dictation on a couple of milliseconds of audio. Sending
    /// `.pressed` alone opened the microphone with nothing in hold-to-talk able to close
    /// it: the next real hold was then refused as busy, and its release finished the
    /// abandoned recording instead, inserting everything the microphone had heard in
    /// between.
    ///
    /// So a click toggles, whatever the shortcut is set to — the same two branches
    /// `pressToToggle` already uses, reached without inventing a keypress. What starts a
    /// dictation this way is a control, and a control is still there to stop it.
    public func toggleFromControl() async {
        if await pipeline.currentState.isListening {
            stopWatchingTheLimit()
            cue.playStop()
            await pipeline.finishRecording()
        } else {
            await beginListening()
        }
    }

    private func beginListening() async {
        await pipeline.startRecording()
        // Only once the pipeline is actually listening, so a refused microphone does
        // not make a sound as though everything had worked.
        if await pipeline.currentState.isListening {
            cue.playStart()
            watchTheLimit()
        }
    }

    /// Warns before the cap and finishes at it, keeping the words. See `Docs/stuck-recording.md`.
    private func watchTheLimit() {
        limitTask?.cancel()
        limitTask = Task { [weak self, clock, limit, onAdvice] in
            do {
                try await clock.sleep(for: limit.warnAfter)
                onAdvice(limit.advice(at: limit.warnAfter))
                try await clock.sleep(for: limit.stopAfter - limit.warnAfter)
            } catch {
                // Cancelled, which is the ordinary end of every dictation.
                return
            }
            onAdvice(.finishNow)
            await self?.finishAtTheLimit()
        }
    }

    /// Ends a dictation that reached the cap, keeping every word of it.
    private func finishAtTheLimit() async {
        guard await pipeline.currentState.isListening else { return }
        cue.playStop()
        await pipeline.finishRecording()
        stopWatchingTheLimit()
    }

    private func stopWatchingTheLimit() {
        limitTask?.cancel()
        limitTask = nil
        onAdvice(.keepGoing)
    }

    private func endHold() async {
        defer { pressedAt = nil }
        stopWatchingTheLimit()
        guard await pipeline.currentState.isListening else { return }

        if let pressedAt, pressedAt.duration(to: clock.now) < Self.minimumHold {
            await pipeline.cancel()
            return
        }

        cue.playStop()
        await pipeline.finishRecording()
    }
}
