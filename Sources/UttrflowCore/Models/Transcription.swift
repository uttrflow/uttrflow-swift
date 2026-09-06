// What a speech engine hands back: words, timed segments and the transcription that holds them.

/// One word, and how sure the recogniser is of it.
public struct TranscribedWord: Sendable, Equatable {
    /// The word as recognised.
    public let text: String
    /// 0 to 1; travels because correction only touches a word the recogniser is unsure about.
    public let confidence: Double

    /// A word with its confidence.
    public init(text: String, confidence: Double) {
        self.text = text
        self.confidence = confidence
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

    /// A segment, with words only when the engine supplies them.
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

    /// A transcription; everything but the text is optional.
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
