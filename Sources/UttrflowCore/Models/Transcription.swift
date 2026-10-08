// What a speech engine hands back: words, timed segments and the transcription that holds them.

/// One word, and how sure the recogniser is of it.
public struct TranscribedWord: Sendable, Equatable {
    /// The word as recognised.
    public let text: String
    /// 0 to 1, converted from ``certainty``; travels because correction only touches a word the recogniser is unsure about.
    public let confidence: Double
    /// The typed score the confidence was converted from.
    public let certainty: WordCertainty
    /// Whether an override wrote this word, so no later layer may rewrite it; a fact apart from the score.
    public let settled: Bool
    /// Where the word begins in the audio; nil when the recogniser did not time it.
    public let start: Duration?
    /// Where the word ends in the audio; nil when the recogniser did not time it.
    public let end: Duration?
    /// The decoder's evidence for each of the word's tokens; empty when the recogniser did not report it.
    package let tokens: [TokenEvidence]

    /// A word with its confidence, and its place in the audio when the recogniser timed it.
    public init(
        text: String, confidence: Double, settled: Bool = false,
        start: Duration? = nil, end: Duration? = nil
    ) {
        self.init(
            text: text, certainty: .reported(ReportedCertainty(probability: confidence)), settled: settled,
            start: start, end: end, tokens: [])
    }

    /// A word scored from the decoder's evidence for its tokens, or by the engine's value when it has none.
    package init(
        text: String, confidence: Double, settled: Bool = false,
        start: Duration? = nil, end: Duration? = nil, tokens: [TokenEvidence]
    ) {
        let certainty = DecoderCertainty(tokens: tokens).map(WordCertainty.decoder)
        self.init(
            text: text, certainty: certainty ?? .reported(ReportedCertainty(probability: confidence)),
            settled: settled, start: start, end: end, tokens: tokens)
    }

    private init(
        text: String, certainty: WordCertainty, settled: Bool,
        start: Duration?, end: Duration?, tokens: [TokenEvidence]
    ) {
        self.text = text
        self.confidence = certainty.gateConfidence
        self.certainty = certainty
        self.settled = settled
        self.start = start
        self.end = end
        self.tokens = tokens
    }
}

/// The recogniser decoder's own judgement of one segment, as it computes it while decoding.
public struct SegmentReliability: Sendable, Equatable {
    /// The sampling temperature of the kept decode; above 0 means hotter retries spent effort on it.
    public let temperature: Double
    /// The mean log-probability of the segment's tokens.
    public let averageLogProbability: Double
    /// The decoder's probability that the segment holds no speech, 0 to 1.
    public let noSpeechProbability: Double
    /// How much the segment's text compresses; a high ratio means repetition.
    public let compressionRatio: Double

    public init(
        temperature: Double, averageLogProbability: Double, noSpeechProbability: Double,
        compressionRatio: Double
    ) {
        self.temperature = temperature
        self.averageLogProbability = averageLogProbability
        self.noSpeechProbability = noSpeechProbability
        self.compressionRatio = compressionRatio
    }
}

/// One timed span of recognised speech.
public struct TranscriptionSegment: Sendable, Equatable {
    /// The text of the span.
    public let text: String
    /// Where the span begins in the audio.
    public let start: Duration
    /// Where the span ends in the audio.
    public let end: Duration
    /// The words inside when the recogniser reports them; empty means "not reported", never "all confident".
    public let words: [TranscribedWord]
    /// The decoder's judgement of the span when reported; absent means "not reported", never "reliable".
    public let reliability: SegmentReliability?

    /// A segment, with words and the decoder's judgement only when the engine supplies them.
    public init(
        text: String, start: Duration, end: Duration, words: [TranscribedWord] = [],
        reliability: SegmentReliability? = nil
    ) {
        self.text = text
        self.start = start
        self.end = end
        self.words = words
        self.reliability = reliability
    }
}

/// The raw output of a ``SpeechEngine``, before any AI clean-up.
public struct Transcription: Sendable, Equatable {
    /// Verbatim recognised text, including filler words and missing punctuation.
    public let text: String
    /// The language the engine detected, when it reports one.
    public let detectedLanguage: DetectedLanguage?
    /// Timed segments, when the engine provides them. May be empty.
    public let segments: [TranscriptionSegment]
    /// Length of the audio that produced this transcription.
    public let audioDuration: Duration
    /// What the recogniser spent beyond one decode, where it reports it.
    public let effort: DecodeEffort
    /// Personal dictionary spellings that survived the recogniser's token budget.
    public let vocabularyPrompt: [String]
    /// Whether the recogniser could condition the decode on the user's words.
    public let conditioning: DecodeConditioning

    /// A transcription; everything but the text is optional.
    public init(
        text: String,
        detectedLanguage: DetectedLanguage? = nil,
        segments: [TranscriptionSegment] = [],
        audioDuration: Duration = .zero,
        effort: DecodeEffort = .none,
        vocabularyPrompt: [String] = [],
        conditioning: DecodeConditioning = .available
    ) {
        self.text = text
        self.detectedLanguage = detectedLanguage
        self.segments = segments
        self.audioDuration = audioDuration
        self.effort = effort
        self.vocabularyPrompt = vocabularyPrompt
        self.conditioning = conditioning
    }

    /// `true` when recognition contains no letter or digit — silence, or noise only.
    public var isBlank: Bool {
        !text.contains { $0.isLetter || $0.isNumber }
    }
}
