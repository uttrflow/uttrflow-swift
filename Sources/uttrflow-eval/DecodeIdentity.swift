// The engine identity a stored decode is filed under, built once for the command that writes dumps and those that read them.
import UttrflowEval
private import UttrflowCore
private import UttrflowSpeech

extension DecodeEngineIdentity {
    /// What `transcribe` decodes the recorded corpus under: the model's pins, the compute plan and the decoding options.
    static func corpusDecode(
        variant: String, weightsRevision: String, tokenizerRevision: String, compute: String,
        hintLanguage: Bool
    ) -> Self {
        DecodeEngineIdentity(
            engineVersion: "\(SpeechEngineKind.whisperKit.rawValue) \(variant) on \(compute)",
            weightsRevision: weightsRevision, tokenizerRevision: tokenizerRevision,
            // `transcribe` primes the decoder with no vocabulary, so every passage shares the empty prompt.
            promptDigest: digest(of: ""),
            optionsDigest: digest(
                of: VocabularyPrompt.unpromptedOptionsDescription
                    + (hintLanguage ? "\nlanguage hinted per passage" : "")))
    }
}
