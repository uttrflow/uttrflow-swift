// The run of tokens forced ahead of a transcript, and the decoding rules measured from it.
import WhisperKit

/// The prefill WhisperKit forces before the transcript, counted once. See `Docs/speech-vocabulary-prompt.md`.
struct DecoderPrefill {
    /// Tokens force-fed before the first sampled one, which is the `sampleBegin` every logits filter needs.
    let count: Int

    /// The prefill for a decode conditioned on `promptTokens`, after the trimming WhisperKit applies to them.
    init(promptTokens: [Int]?, specialTokenBegin: Int, isMultilingual: Bool) {
        let prompt = Self.forcedPrompt(
            from: promptTokens, specialTokenBegin: specialTokenBegin)
        // Start-of-transcript and the timestamps token, plus a language and a task where the model has them.
        let opening = 2 + (isMultilingual ? 2 : 0)
        // A prompt that survives trimming arrives behind a start-of-previous token; one that does not is dropped whole.
        count = opening + (prompt.isEmpty ? 0 : prompt.count + 1)
    }

    /// The prompt the decoder is actually fed: its last ``VocabularyPrompt/maximumTokens``, instructions removed.
    static func forcedPrompt(from promptTokens: [Int]?, specialTokenBegin: Int) -> [Int] {
        guard let promptTokens else { return [] }
        return promptTokens.suffix(VocabularyPrompt.maximumTokens).filter { $0 < specialTokenBegin }
    }

    /// The timestamp rules, told where sampling begins because WhisperKit's own copy cannot see past a prompt.
    func logitsFilters(specialTokens: SpecialTokens) -> [any LogitsFiltering] {
        [
            TimestampRulesFilter(
                specialTokens: specialTokens,
                sampleBegin: count,
                maxInitialTimestampIndex: nil,
                // Reported as English-only so the rules trust this `sampleBegin` instead of hunting for a task token.
                isModelMultilingual: false
            )
        ]
    }
}
