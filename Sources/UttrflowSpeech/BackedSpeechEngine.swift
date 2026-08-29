public import UttrflowCore

/// The one speech engine.
///
/// Every rule that matters — load once, refuse audio too short to mean anything, map
/// the result the same way regardless of recogniser — lives here, so swapping
/// WhisperKit for the system transcriber changes which backend is handed in and
/// nothing else. That is what makes the choice in ``EngineConfiguration`` a flag
/// rather than a rewrite.
public actor BackedSpeechEngine: SpeechEngine {
    /// Audio shorter than this cannot carry a word, and recognisers hallucinate on it.
    public static let minimumDuration = Duration.milliseconds(250)

    public nonisolated let kind: SpeechEngineKind

    private let backend: any TranscriptionBackend
    private let vocabulary: (any VocabularySource)?
    private var isLoaded = false

    /// - Parameters:
    ///   - kind: Which recogniser this is, for anything that reports it.
    ///   - backend: The recogniser itself.
    ///   - vocabulary: Words to bias the recogniser towards, asked for once per
    ///     dictation. Absent by default, because biasing is worth having and not worth
    ///     requiring.
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

        // Loading here as well as in `prepare` means a caller that forgot to prepare
        // gets a slow first transcription rather than a failure.
        try await prepare()

        // Read now rather than at construction: which of the user's words matter depends
        // on what is on screen, and that is only true of this dictation.
        let words = await vocabulary?.vocabulary() ?? []
        let raw = try await backend.transcribe(
            audio.samples, languageHint: options.languageHint, biasedTowards: words)
        return raw.transcription(audioDuration: audio.duration)
    }
}
