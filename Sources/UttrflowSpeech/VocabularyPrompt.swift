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
enum VocabularyPrompt {
    /// The most prompt tokens WhisperKit decodes, which is 111 rather than the model's 448.
    static let maximumTokens = 111

    /// The sentence the user's words are offered inside, which is what makes the decoder hear them.
    static let opening = " The words used here are"
    /// Closed like a sentence, for the same reason it is opened like one.
    static let closing = "."

    /// The prompt for `words`, most valuable first, packed whole words only, or `nil` if none fit.
    static func tokens(for words: [String], using tokenizer: some PromptTokenizer) -> [Int]? {
        let opening = ids(of: opening, using: tokenizer)
        let closing = ids(of: closing, using: tokenizer)
        guard !opening.isEmpty, !closing.isEmpty else { return nil }

        var body: [Int] = []
        for word in words {
            // The separator belongs to the word, so dropping one leaves no comma behind.
            let piece = ids(of: (body.isEmpty ? " " : ", ") + word, using: tokenizer)
            guard !piece.isEmpty,
                opening.count + body.count + piece.count + closing.count <= maximumTokens
            else { continue }
            body += piece
        }
        return body.isEmpty ? nil : opening + body + closing
    }

    /// How many tokens run before the transcript begins, which ``PromptPrefillGuard`` waits out.
    static func forcedPrefillLength(promptLength: Int, isMultilingual: Bool) -> Int {
        // start-of-previous, start-of-transcript, and the timestamps token.
        let fixed = 3
        return promptLength + fixed + (isMultilingual ? 2 : 0)
    }

    /// What the recogniser is asked for, carrying a prompt only when one could be built.
    static func decodingOptions(
        languageHint: LanguageCode?,
        vocabulary: [String] = [],
        tokenizer: (any PromptTokenizer)? = nil
    ) -> DecodingOptions {
        DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: languageHint?.value,
            // Detecting is what mixed-language speech needs.
            detectLanguage: languageHint == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            // The only way to get a per-word probability out of WhisperKit, which correction needs.
            wordTimestamps: true,
            // Re-forced for every 30-second window, so a long dictation is biased throughout.
            promptTokens: tokenizer.flatMap { tokens(for: vocabulary, using: $0) }
        )
    }

    /// The ids for one piece, minus the special tokens, so the budget matches what survives.
    private static func ids(of text: String, using tokenizer: some PromptTokenizer) -> [Int] {
        tokenizer.encode(text: text).filter { $0 < tokenizer.firstSpecialToken }
    }
}
