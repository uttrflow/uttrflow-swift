// The SpeechEngine the product uses, applying its rules over any TranscriptionBackend.
public import UttrflowCore

/// The one speech engine: every rule that outlives a choice of recogniser lives here.
public actor BackedSpeechEngine: SpeechEngine {
    /// Audio shorter than this cannot carry a word, and recognisers hallucinate on it.
    public static let minimumDuration = Duration.milliseconds(250)

    public nonisolated let kind: SpeechEngineKind

    private let backend: any TranscriptionBackend
    private var isLoaded = false
    /// How long the recogniser may sit unused before it is let go; `nil` holds it for the life of the engine.
    private let idleAfter: Duration?
    /// When the recogniser last loaded or answered, which the idle watch measures from.
    private var lastUsed = ContinuousClock.now
    private var watch: Task<Void, Never>?
    /// The latest load `warm` started; internal so a test can wait for it.
    private(set) var warming: Task<Void, Never>?
    /// One call into the recogniser at a time, since actor reentrancy lets a second in at every await. See `Docs/speech-engines.md`.
    private let turn = RecogniserTurn()

    public init(
        kind: SpeechEngineKind,
        backend: any TranscriptionBackend,
        idleAfter: Duration? = nil
    ) {
        self.kind = kind
        self.backend = backend
        self.idleAfter = idleAfter
    }

    /// Whether the recogniser is loaded now; internal so a test can read it.
    var holdsTheRecogniser: Bool { isLoaded }

    /// The idle watch, which ends once it lets the recogniser go; internal so a test can wait for it.
    var watching: Task<Void, Never>? { watch }

    public func prepare() async throws(SpeechEngineError) {
        guard !isLoaded else { return }
        try await turn.take()
        defer { turn.release() }
        try await loadIfNeeded()
    }

    /// Starts loading the recogniser without waiting, so a load overlaps the recording it is for.
    public func warm() async {
        guard !isLoaded else { return }
        warming = Task { try? await self.prepare() }
    }

    /// Lets the recogniser go once no call holds it, so its memory returns until the next dictation.
    public func release() async {
        guard isLoaded else { return }
        do { try await turn.take() } catch { return }
        defer { turn.release() }
        await unloadHeld()
    }

    /// Unloads the recogniser; the caller holds the turn.
    private func unloadHeld() async {
        guard isLoaded else { return }
        watch?.cancel()
        watch = nil
        await backend.unload()
        isLoaded = false
    }

    /// Loads the recogniser unless a call that held the turn earlier already did; the caller holds the turn.
    private func loadIfNeeded() async throws(SpeechEngineError) {
        defer { touched() }
        guard !isLoaded else { return }
        try await backend.load()
        isLoaded = true
    }

    /// Marks the recogniser as just used and keeps an idle watch running while it is loaded.
    private func touched() {
        lastUsed = .now
        guard isLoaded, let idleAfter, watch == nil else { return }
        watch = Task { [weak self] in
            var wait = idleAfter
            while !Task.isCancelled {
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled, let self else { return }
                guard let left = await self.releaseIfIdle(after: idleAfter) else { return }
                wait = left
            }
        }
    }

    /// Lets the recogniser go when unused for `idleAfter`; returns how long to wait before asking again, or `nil` once let go.
    private func releaseIfIdle(after idleAfter: Duration) async -> Duration? {
        let idle = lastUsed.duration(to: .now)
        guard idle >= idleAfter else { return idleAfter - idle }
        do { try await turn.take() } catch { return nil }
        defer { turn.release() }
        // Measured again under the turn, since a dictation may have run while this waited for it.
        let stillIdle = lastUsed.duration(to: .now)
        guard stillIdle >= idleAfter else { return idleAfter - stillIdle }
        watch = nil
        await backend.unload()
        isLoaded = false
        return nil
    }

    public func transcribe(
        _ audio: AudioSamples,
        options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        guard audio.duration >= Self.minimumDuration else { throw .audioTooShort }

        // Before the recogniser: nothing downstream can tell invented words from spoken ones.
        guard let speech = audio.speechOnly() else { throw .nothingHeard }
        guard speech.audio.duration >= Self.minimumDuration else { throw .nothingHeard }

        // Held until the recogniser answers, so an abandoned decode still running is waited for rather than overlapped.
        try await turn.take()
        defer { turn.release() }

        // A caller that forgot to prepare gets a slow first transcription, not a failure.
        try await loadIfNeeded()

        // Ranked once for the dictation and carried in, so every piece is biased towards the same words.
        let raw = try await backend.transcribe(
            Self.padded(speech.audio, to: backend.minimumDuration),
            languageHint: options.languageHint, biasedTowards: options.vocabulary)
        touched()
        // The original duration, not the trimmed one: it is what the user spoke for.
        return raw.transcription(audioDuration: audio.duration, startingAt: speech.start)
    }

    /// The samples with silence appended up to `minimum`, so a word shorter than the recogniser's floor still decodes.
    static func padded(_ audio: AudioSamples, to minimum: Duration) -> [Float] {
        let needed = Int((minimum / .seconds(1) * Double(audio.sampleRate)).rounded(.up))
        guard audio.samples.count < needed else { return audio.samples }
        return audio.samples + Array(repeating: 0, count: needed - audio.samples.count)
    }
}
