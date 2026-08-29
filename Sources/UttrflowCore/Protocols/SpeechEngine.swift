/// How a transcription should be performed.
public struct TranscriptionOptions: Sendable, Equatable {
    /// A language to bias towards. `nil` lets the engine detect the language, which
    /// is what mixed-language speech needs.
    public let languageHint: LanguageCode?

    public init(languageHint: LanguageCode? = nil) {
        self.languageHint = languageHint
    }

    public static let automatic = TranscriptionOptions()
}

/// Turns captured audio into text.
public protocol SpeechEngine: Sendable {
    var kind: SpeechEngineKind { get }

    /// Loads whatever the engine needs before its first transcription, so that the
    /// cost is paid at launch rather than on the user's first recording.
    func prepare() async throws(SpeechEngineError)

    func transcribe(
        _ audio: AudioSamples,
        options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription
}
