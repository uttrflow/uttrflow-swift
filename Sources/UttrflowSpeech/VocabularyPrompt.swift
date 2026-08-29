import UttrflowCore
import WhisperKit

/// A tokeniser, reduced to the two things a conditioning prompt needs from it.
///
/// The seam exists so that the arithmetic below can be checked against a tokeniser a
/// test writes in three lines, rather than against a 646 MB download. Its only real
/// implementation adapts WhisperKit's own, and lives beside the recogniser.
protocol PromptTokenizer {
    /// The ids the recogniser reads `text` as.
    func encode(text: String) -> [Int]

    /// The lowest id that instructs the decoder rather than spelling part of a word.
    var firstSpecialToken: Int { get }
}

/// The user's own words, turned into the prompt Whisper is conditioned on *before* it
/// decodes anything.
///
/// This is where a personal dictionary is worth the most. Rewriting "utter flow" to
/// "Uttrflow" afterwards is a repair, and one that only fires when the recogniser
/// happened to produce something close enough to match; putting the word in front of
/// the decoder makes it hear the word.
enum VocabularyPrompt {
    /// The most prompt tokens WhisperKit will actually decode.
    ///
    /// Not the model's 448-token context, and not half of it either. WhisperKit trims
    /// the prompt to `(Constants.maxTokenContext / 2) - 1`, and `maxTokenContext` is
    /// itself `Int(448 / 2)` — 224 — so the real ceiling is 111. (WhisperKit 0.18:
    /// `Core/TextDecoder.swift:339` for the expression, `Core/Models.swift:1420` for
    /// the constant.)
    ///
    /// Truncating here rather than leaving it to the decoder is the whole point.
    /// WhisperKit keeps the *last* 111 tokens and drops the rest without a word, so a
    /// vocabulary ranked best-first would lose precisely the words worth having. It is
    /// not a rare case either: ``WorkingSet`` offers up to 96 words and a technical word
    /// is seldom one token, so the budget usually binds long before the word count does.
    static let maximumTokens = 111

    /// The sentence the user's words are offered inside.
    ///
    /// Not decoration, and the single most surprising thing measured here. Handed a bare
    /// run of words — `Uttrflow Nikhil PaymentSheet` — the decoder barely moves: it still
    /// heard "KidPit". Handed the same words inside this sentence it heard "Uttrflow",
    /// with three words in the list and again with fourteen. Whisper's prompt is trained
    /// as the *transcript that came before*, so text shaped like a transcript is what it
    /// knows how to condition on; a glossary is not.
    static let opening = " The words used here are"
    /// Closed like a sentence, for the same reason it is opened like one.
    static let closing = "."

    /// The conditioning prompt for `words`, or `nil` when there is nothing to condition
    /// on.
    ///
    /// Packed word by word rather than truncated mid-sequence: half of `PaymentSheet` in
    /// the prompt biases the decoder towards something the user has never said. A word
    /// too long for what is left is skipped rather than ending the packing, so one
    /// forty-token monster cannot cost the fifty ordinary words ranked behind it.
    ///
    /// - Parameters:
    ///   - words: The user's own spellings, most valuable first.
    ///   - tokenizer: The recogniser's own tokeniser, so the ids are the ids it will read.
    /// - Returns: At most ``maximumTokens`` ids, or `nil` when nothing survived.
    static func tokens(for words: [String], using tokenizer: some PromptTokenizer) -> [Int]? {
        let opening = ids(of: opening, using: tokenizer)
        let closing = ids(of: closing, using: tokenizer)
        guard !opening.isEmpty, !closing.isEmpty else { return nil }

        var body: [Int] = []
        for word in words {
            // The separator belongs to the word rather than sitting between words,
            // because dropping a word that will not fit must not leave its comma behind.
            let piece = ids(of: (body.isEmpty ? " " : ", ") + word, using: tokenizer)
            guard !piece.isEmpty,
                opening.count + body.count + piece.count + closing.count <= maximumTokens
            else { continue }
            body += piece
        }
        return body.isEmpty ? nil : opening + body + closing
    }

    /// How many tokens WhisperKit forces through the decoder before the transcript
    /// begins, when it has been given a prompt of `promptLength` tokens.
    ///
    /// `[<|startofprev|>] + prompt + [<|startoftranscript|>, language, task, timestamps]`
    /// for a multilingual model, which drops the language and task tokens when the model
    /// only knows English. (WhisperKit 0.18, `Core/TextDecoder.swift:313-342`.)
    ///
    /// Needed because WhisperKit ends a window the moment the sampler predicts the end
    /// token — including while it is still force-feeding the prompt, when whatever the
    /// sampler produced is thrown away anyway. Every conditioning prompt trips this and
    /// returns an empty transcript, which is why the recogniser has to hold that token
    /// shut until this many have gone through. See ``PromptPrefillGuard``.
    static func forcedPrefillLength(promptLength: Int, isMultilingual: Bool) -> Int {
        // start-of-previous, the prompt, start-of-transcript, and the timestamps token.
        let fixed = 3
        return promptLength + fixed + (isMultilingual ? 2 : 0)
    }

    /// What the recogniser is asked to do for one transcription.
    ///
    /// An empty vocabulary, an absent tokeniser, or one that nothing survives leaves
    /// these options exactly as they were before any of this existed. That is the trade
    /// being made deliberately: a word missing from the prompt costs the user a
    /// correction, and a dictation refused because a word would not encode costs them
    /// the dictation.
    ///
    /// - Parameters:
    ///   - languageHint: A language to pin. `nil` asks the recogniser to detect one,
    ///     which is what mixed-language speech needs.
    ///   - vocabulary: The user's own spellings, most valuable first.
    ///   - tokenizer: The recogniser's tokeniser, absent until its model has loaded.
    /// - Returns: Options carrying a conditioning prompt only when one could be built.
    static func decodingOptions(
        languageHint: LanguageCode?,
        vocabulary: [String] = [],
        tokenizer: (any PromptTokenizer)? = nil
    ) -> DecodingOptions {
        DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: languageHint?.value,
            // Detecting is what mixed-language speech needs, and is only
            // possible when the caller has not pinned a language.
            detectLanguage: languageHint == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            // Word timings are asked for because they are the only way to get a
            // per-word probability out of WhisperKit, and correction's first condition
            // is that the recogniser was unsure. Measured on the shipping turbo model:
            // +4.1ms on a 3.3s clip and +19.1ms on a 24.3s one, which is 0.9% and 1.4%
            // of those transcriptions. Cheap enough that the alternative — a constant
            // confidence, making the condition either vacuous or unsatisfiable — was
            // never worth considering.
            wordTimestamps: true,
            // Applied once, ahead of the prefill, and re-forced for every 30-second
            // window: WhisperKit builds the decoder's initial prompt before its seek
            // loop and never overwrites it, so a two-minute dictation is biased just as
            // strongly at the end as at the start. It costs the prefill cache and part
            // of each window's decode budget, which is why the budget above is a ceiling
            // rather than a target.
            promptTokens: tokenizer.flatMap { tokens(for: vocabulary, using: $0) }
        )
    }

    /// The ids for one piece of the prompt, with anything the decoder would read as an
    /// instruction removed.
    ///
    /// WhisperKit discards those itself, so filtering here as well is what keeps the
    /// count being budgeted equal to the count that survives.
    private static func ids(of text: String, using tokenizer: some PromptTokenizer) -> [Int] {
        tokenizer.encode(text: text).filter { $0 < tokenizer.firstSpecialToken }
    }
}
