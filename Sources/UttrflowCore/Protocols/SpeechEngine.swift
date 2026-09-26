// The speech-engine protocol and the options a transcription takes.

/// How a transcription should be performed.
public struct TranscriptionOptions: Sendable, Equatable {
    /// A language to bias towards; `nil` lets the engine detect it, which mixed-language speech needs.
    public let languageHint: LanguageCode?

    /// The words worth putting in front of the recogniser, ranked once for the dictation, most valuable first.
    public let vocabulary: [String]

    /// Options with an optional language hint and the dictation's vocabulary.
    public init(languageHint: LanguageCode? = nil, vocabulary: [String] = []) {
        self.languageHint = languageHint
        self.vocabulary = vocabulary
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

    /// Starts a load without waiting for it, so a recogniser let go while idle is back by the time the speech ends.
    func warm() async

    /// Transcribes one recording.
    func transcribe(
        _ audio: AudioSamples,
        options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription
}

extension SpeechEngine {
    /// Loads nothing ahead, for an engine that keeps its recogniser for good.
    public func warm() async {}
}
