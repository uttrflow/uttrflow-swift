public import UttrflowCore

/// One word as a recogniser heard it, with a per-word probability. See Docs/speech-engines.md.
public struct RawWord: Sendable, Equatable {
    public let text: String
    public let start: Double
    public let end: Double
    /// How sure the recogniser was, 0 to 1.
    public let probability: Double

    public init(text: String, start: Double, end: Double, probability: Double) {
        self.text = text
        self.start = start
        self.end = end
        self.probability = probability
    }
}

/// One timed span as a recogniser reports it, in seconds.
public struct RawSegment: Sendable, Equatable {
    public let text: String
    public let start: Double
    public let end: Double
    /// The words inside this span when reported; absent means "not reported", never "all confident".
    public let words: [RawWord]?

    public init(text: String, start: Double, end: Double, words: [RawWord]? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.words = words
    }
}

/// What a recogniser produces before the product's rules, free of any recogniser's own types.
public struct RawTranscript: Sendable, Equatable {
    public let text: String
    /// Whatever the recogniser calls the language it heard, unnormalised.
    public let languageIdentifier: String?
    /// The recogniser's own probability for that language, where it reports one.
    public let languageProbability: Double?
    public let segments: [RawSegment]

    public init(
        text: String,
        languageIdentifier: String? = nil,
        languageProbability: Double? = nil,
        segments: [RawSegment] = []
    ) {
        self.text = text
        self.languageIdentifier = languageIdentifier
        self.languageProbability = languageProbability
        self.segments = segments
    }
}

/// A recogniser, reduced to the two things the engine needs from it.
public protocol TranscriptionBackend: Sendable {
    /// Loads whatever the recogniser needs; throws `modelNotInstalled` or `modelLoadFailed`.
    func load() async throws(SpeechEngineError)

    /// Recognises canonical mono samples; a `nil` hint asks the recogniser to detect the language.
    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?
    ) async throws(SpeechEngineError) -> RawTranscript

    /// Recognises with the decoder biased towards `vocabulary`; defaulted, so a recogniser can opt out.
    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?, biasedTowards vocabulary: [String]
    ) async throws(SpeechEngineError) -> RawTranscript
}

extension TranscriptionBackend {
    /// Ignores the vocabulary and transcribes normally; a dropped word costs a correction, not the dictation.
    public func transcribe(
        _ samples: [Float], languageHint: LanguageCode?, biasedTowards vocabulary: [String]
    ) async throws(SpeechEngineError) -> RawTranscript {
        try await transcribe(samples, languageHint: languageHint)
    }
}
