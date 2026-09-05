public import UttrflowCore

/// Turns key presses into dictations; generic over the clock so the minimum hold tests instantly.
public actor DictationController<ClockType: Clock> where ClockType.Duration == Duration {
    /// A hold shorter than this is a slip, cancelled silently rather than reported as too short.
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
    private var forwardingTask: Task<Void, Never>?

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

    /// Watches for the shortcut, or rebinds after ending the old forwarder. See Docs/pipeline-gestures.md.
    public func start(binding: HotkeyBinding) async throws(HotkeyError) {
        forwardingTask?.cancel()
        forwardingTask = nil

        try await monitor.start(binding: binding)
        // Forwarded rather than handled here, so the shortcut queues behind the same single consumer.
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
