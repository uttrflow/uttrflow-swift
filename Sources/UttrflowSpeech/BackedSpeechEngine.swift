// The SpeechEngine the product uses, applying its rules over any TranscriptionBackend.
public import UttrflowCore

/// The one speech engine: every rule that outlives a choice of recogniser lives here.
public actor BackedSpeechEngine: SpeechEngine {
    /// Audio shorter than this cannot carry a word, and recognisers hallucinate on it.
    public static let minimumDuration = Duration.milliseconds(250)

    public nonisolated let kind: SpeechEngineKind

    private let backend: any TranscriptionBackend
    private let vocabulary: (any VocabularySource)?
    private var isLoaded = false

    public init(
        kind: SpeechEngineKind,
        backend: any TranscriptionBackend,
        vocabulary: (any VocabularySource)? = nil
    ) {
        self.kind = kind
        self.backend = backend
        self.vocabulary = vocabulary
    }

    public func prepare() async throws(SpeechEngineError) {
        guard !isLoaded else { return }
        try await backend.load()
        isLoaded = true
    }

    public func transcribe(
        _ audio: AudioSamples,
        options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        guard audio.duration >= Self.minimumDuration else { throw .audioTooShort }

        // Before the recogniser: nothing downstream can tell invented words from spoken ones.
        guard let speech = audio.speechOnly() else { throw .nothingHeard }
        guard speech.audio.duration >= Self.minimumDuration else { throw .nothingHeard }

        // A caller that forgot to prepare gets a slow first transcription, not a failure.
        try await prepare()

        // Read now, because which words matter depends on what is on screen right now.
        let words = await vocabulary?.vocabulary() ?? []
        let raw = try await backend.transcribe(
            speech.audio.samples, languageHint: options.languageHint, biasedTowards: words)
        // The original duration, not the trimmed one: it is what the user spoke for.
        return raw.transcription(audioDuration: audio.duration, startingAt: speech.start)
    }
}
