import UttrflowCore
import WhisperKit

// The personal dictionary, turned into the prompt Whisper is conditioned on.
/// A tokeniser reduced to the two things a conditioning prompt needs, so a test can write one.
protocol PromptTokenizer {
    /// The ids the recogniser reads `text` as.
    func encode(text: String) -> [Int]

    /// The lowest id that instructs the decoder rather than spelling part of a word.
    var firstSpecialToken: Int { get }
}

/// The user's words as the prompt Whisper decodes against. See `Docs/speech-vocabulary-prompt.md`.
public enum VocabularyPrompt {
    /// The most prompt tokens WhisperKit decodes, which is 111 rather than the model's 448.
    static let maximumTokens = 111

    /// The sentence the user's words are offered inside, which is what makes the decoder hear them.
    public static let opening = " The words used here are"
    /// Closed like a sentence, for the same reason it is opened like one.
    static let closing = "."

    /// The exact words and tokens kept in the recogniser prompt.
    struct Packing: Equatable {
        let words: [String]
        let tokens: [Int]?
    }

    /// The prompt for `words`, most valuable first, packed whole words only, or `nil` if none fit.
    static func tokens(for words: [String], using tokenizer: some PromptTokenizer) -> [Int]? {
        packing(for: words, using: tokenizer).tokens
    }

    /// Reports the exact dictionary words represented by the packed prompt.
    static func packing(for words: [String], using tokenizer: some PromptTokenizer) -> Packing {
        let opening = ids(of: opening, using: tokenizer)
        let closing = ids(of: closing, using: tokenizer)
        guard !opening.isEmpty, !closing.isEmpty else { return Packing(words: [], tokens: nil) }

        var body: [Int] = []
        var packedWords: [String] = []
        for word in words {
            // Spaced rather than punctuated: the decoder copies a mark between two listed words into the transcript.
            let piece = ids(of: " " + word, using: tokenizer)
            guard !piece.isEmpty else {
                continue
            }
            guard opening.count + body.count + piece.count + closing.count <= maximumTokens else {
                continue
            }
            body += piece
            packedWords.append(word)
        }
        return Packing(words: packedWords, tokens: body.isEmpty ? nil : opening + body + closing)
    }

    /// Seconds at the end of a clip no window may start in, so WhisperKit decodes nothing from a clip no longer than this.
    static let windowClipTime: Float = 1.0

    /// What the recogniser is asked for, every option named so a WhisperKit upgrade cannot move one unseen.
    static func decodingOptions(
        languageHint: LanguageCode?,
        vocabulary: [String] = [],
        tokenizer: (any PromptTokenizer)? = nil,
        fallback: SpeechFallbackPlan = .shipping
    ) -> DecodingOptions {
        DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: languageHint?.value,
            // Greedy first, so the same audio gives the same words.
            temperature: 0,
            // A window rejected by the thresholds below is retried this much warmer, this many times.
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: fallback.temperatureCount,
            sampleLength: Constants.maxTokenContext,
            topK: 5,
            usePrefillPrompt: true,
            // Detecting is what mixed-language speech needs.
            detectLanguage: languageHint == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            // The only way to get a per-word probability out of WhisperKit, which correction needs.
            wordTimestamps: true,
            maxInitialTimestamp: nil,
            maxWindowSeek: nil,
            // The whole clip, which the engine has already trimmed to its speech.
            clipTimestamps: [],
            // Keeps a window from starting where Whisper invents words; the backend's floor follows it.
            windowClipTime: windowClipTime,
            // Re-forced for every 30-second window, so a long dictation is biased throughout.
            promptTokens: tokenizer.flatMap { packing(for: vocabulary, using: $0).tokens },
            prefixTokens: nil,
            suppressBlank: false,
            suppressTokens: [],
            // Whisper's own tests for a window of repetition, low confidence or silence.
            compressionRatioThreshold: 2.4,
            logProbThreshold: fallback.logProbThreshold,
            firstTokenLogProbThreshold: -1.5,
            noSpeechThreshold: 0.6,
            concurrentWorkerCount: 16,
            // None of WhisperKit's own, because the product cuts its pieces at pauses. See `Docs/early-transcription.md`.
            chunkingStrategy: nil
        )
    }

    /// The ids for one piece, minus the special tokens, so the budget matches what survives.
    private static func ids(of text: String, using tokenizer: some PromptTokenizer) -> [Int] {
        tokenizer.encode(text: text).filter { $0 < tokenizer.firstSpecialToken }
    }
}
