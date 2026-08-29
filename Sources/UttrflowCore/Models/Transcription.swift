/// One timed span of recognised speech.
/// One word, and how sure the recogniser was of it.
public struct TranscribedWord: Sendable, Equatable {
    public let text: String
    /// 0 to 1. The reason this travels: correction only touches a word the recogniser
    /// was unsure about, and nothing else in the transcript can answer that.
    public let confidence: Double

    public init(text: String, confidence: Double) {
        self.text = text
        self.confidence = confidence
    }
}

public struct TranscriptionSegment: Sendable, Equatable {
    public let text: String
    public let start: Duration
    public let end: Duration
    /// The words inside, when the recogniser reports them.
    ///
    /// Absent means "not reported", never "all confident". A caller that treats the two
    /// alike turns silence into certainty, which is exactly the mistake that would make
    /// correction rewrite good sentences.
    public let words: [TranscribedWord]

    public init(
        text: String, start: Duration, end: Duration, words: [TranscribedWord] = []
    ) {
        self.text = text
        self.start = start
        self.end = end
        self.words = words
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

    public init(
        text: String,
        detectedLanguage: DetectedLanguage? = nil,
        segments: [TranscriptionSegment] = [],
        audioDuration: Duration = .zero
    ) {
        self.text = text
        self.detectedLanguage = detectedLanguage
        self.segments = segments
        self.audioDuration = audioDuration
    }

    /// `true` when the engine recognised nothing usable — silence, or noise only.
    public var isBlank: Bool {
        text.allSatisfy(\.isWhitespace)
    }
}
