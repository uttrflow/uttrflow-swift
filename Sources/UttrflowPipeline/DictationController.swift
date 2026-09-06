// Turns key presses and clicks into dictations.
public import UttrflowCore

/// Turns key presses into dictations; generic over the clock so the minimum hold tests instantly.
public actor DictationController<ClockType: Clock> where ClockType.Duration == Duration {
    /// A hold shorter than this is a slip, cancelled silently rather than reported as too short.
    public static var minimumHold: Duration { .milliseconds(200) }

    /// Two slips closer together than this are one double tap. See Docs/pipeline-gestures.md.
    public static var doubleTapWindow: Duration { .milliseconds(450) }

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
    /// When the last slip ended, so the next one can tell whether it is the second of a pair.
    private var lastTapEndedAt: ClockType.Instant?
    /// Whether the microphone was left open by a double tap, and so waits for another to close it.
    private var isHandsFree = false
    /// Every gesture from every source, handled one at a time. See Docs/pipeline-gestures.md.
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
        // Forwarded once for the controller's life: an `AsyncStream` has room for one reader.
        let events = monitor.events
        Task { [weak self] in
            for await event in events { self?.submit(event) }
        }
    }

    /// Queues a gesture from any source behind whatever is in flight, and returns at once.
    public nonisolated func submit(_ event: HotkeyEvent) {
        gestureSink.yield(event)
    }

    private func consumeGestures() async {
        for await event in gestures {
            await handle(event)
        }
    }

    /// Watches for the shortcut, or rebinds to another one. See Docs/pipeline-gestures.md.
    public func start(binding: HotkeyBinding) async throws(HotkeyError) {
        try await monitor.start(binding: binding)
    }

    public func stop() {
        stopWatchingTheLimit()
        // Stopped last, so the release it owes for a hold still reaches the forwarder.
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
            // Hands-free is already listening; pressing again is the start of the gesture that ends it.
            if !isHandsFree { await beginListening() }

        case (.holdToTalk, .released):
            await endHold()

        case (.pressToToggle, .pressed):
            await toggleListening()

        // Releasing does nothing in toggle mode: the next press is what stops it.
        case (.pressToToggle, .released):
            break
        }
    }

    /// Toggles a dictation from a click, which has no release. See Docs/pipeline-gestures.md.
    public func toggleFromControl() async {
        await toggleListening()
    }

    /// Finishes the dictation under way, or begins one.
    private func toggleListening() async {
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
        // Only once the pipeline is listening, so a refused microphone does not sound as though it worked.
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
        let pressed = pressedAt
        defer { pressedAt = nil }
        guard await pipeline.currentState.isListening else { return }

        let now = clock.now
        let wasTap = pressed.map { $0.duration(to: now) < Self.minimumHold } ?? false
        if wasTap, let last = lastTapEndedAt, last.duration(to: now) < Self.doubleTapWindow {
            lastTapEndedAt = nil
            isHandsFree ? await stopHandsFree() : (isHandsFree = true)
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
        // Letting go of a key that was never held is what ends a hold, and hands-free has no hold.
        guard !isHandsFree else { return }
        stopWatchingTheLimit()
        cue.playStop()
        await pipeline.finishRecording()
    }

    /// Closes a microphone a double tap left open, which another double tap is the only way to do.
    private func stopHandsFree() async {
        isHandsFree = false
        stopWatchingTheLimit()
        cue.playStop()
        await pipeline.finishRecording()
    }
}
