// The speech-engine protocol and the options a transcription takes.

/// How a transcription should be performed.
public struct TranscriptionOptions: Sendable, Equatable {
    /// A language to bias towards; `nil` lets the engine detect it, which mixed-language speech needs.
    public let languageHint: LanguageCode?

    /// Options with an optional language hint.
    public init(languageHint: LanguageCode? = nil) {
        self.languageHint = languageHint
    }

    /// No hint: the engine detects the language.
    public static let automatic = TranscriptionOptions()
}

/// Turns captured audio into text.
public protocol SpeechEngine: Sendable {
    /// Which kind this engine is.
    var kind: SpeechEngineKind { get }

    /// Loads whatever the engine needs, so the cost is paid at launch rather than on the first recording.
    func prepare() async throws(SpeechEngineError)

    /// Transcribes one recording.
    func transcribe(
        _ audio: AudioSamples,
        options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription
}
