public import UttrflowCore

/// One word as a recogniser heard it, with how sure it was.
///
/// The probability is the whole reason this type exists. Correction's first condition is
/// that the recogniser was unsure, and without a per-word figure that condition can only
/// be answered with a constant — which makes it either always true, and the engine
/// rewrites constantly, or never true, and the engine can never fire. Neither is a
/// feature. Measured on the shipping model, the spread is real: "up" 0.41 against 0.99
/// for most content words in the same sentence.
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
    /// The words inside this span, when the recogniser reports them.
    ///
    /// Optional because not every recogniser does: Apple's has no equivalent, and
    /// WhisperKit only fills it when asked for word timings. Absent means "not reported",
    /// never "all confident" — a caller that cannot tell the two apart would turn silence
    /// into certainty.
    public let words: [RawWord]?

    public init(text: String, start: Double, end: Double, words: [RawWord]? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.words = words
    }
}

/// What a recogniser produces, before any of the product's own rules are applied.
///
/// Deliberately free of any recogniser's types: both WhisperKit and the system
/// transcriber reduce to this, which is why one engine can drive either.
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
    /// Loads whatever the recogniser needs before its first use.
    ///
    /// - Throws: ``SpeechEngineError/modelNotInstalled`` when its files are missing,
    ///   or ``SpeechEngineError/modelLoadFailed(description:)`` when they will not load.
    func load() async throws(SpeechEngineError)

    /// Recognises canonical-format samples.
    ///
    /// - Parameters:
    ///   - samples: Mono samples at ``AudioSamples/canonicalSampleRate``.
    ///   - languageHint: A language to bias towards. `nil` asks the recogniser to work
    ///     it out, which is what mixed-language speech needs.
    /// - Returns: The recogniser's output, before any of the product's rules.
    /// - Throws: ``SpeechEngineError/transcriptionFailed(description:)``.
    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?
    ) async throws(SpeechEngineError) -> RawTranscript

    /// Recognises canonical-format samples with the decoder conditioned towards the
    /// user's own words, so that it hears them rather than being corrected afterwards.
    ///
    /// Has a default implementation, which is what makes it optional: a recogniser with
    /// no way to bias its decoder — the system transcriber has none — inherits the
    /// default and is untouched by any of this.
    ///
    /// - Parameters:
    ///   - samples: Mono samples at ``AudioSamples/canonicalSampleRate``.
    ///   - languageHint: A language to bias towards, as above.
    ///   - vocabulary: Words to favour, most valuable first. A recogniser may use fewer
    ///     than it is given, and must never fail because of one.
    /// - Returns: The recogniser's output, before any of the product's rules.
    /// - Throws: ``SpeechEngineError/transcriptionFailed(description:)``.
    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?, biasedTowards vocabulary: [String]
    ) async throws(SpeechEngineError) -> RawTranscript
}

extension TranscriptionBackend {
    /// Ignores the vocabulary and transcribes normally.
    ///
    /// Dropping the words silently is the right failure for a recogniser that cannot use
    /// them: losing a word from a prompt costs the user a correction, and refusing the
    /// audio costs them the dictation.
    public func transcribe(
        _ samples: [Float], languageHint: LanguageCode?, biasedTowards vocabulary: [String]
    ) async throws(SpeechEngineError) -> RawTranscript {
        try await transcribe(samples, languageHint: languageHint)
    }
}
