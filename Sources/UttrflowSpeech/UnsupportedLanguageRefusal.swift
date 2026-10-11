// Decides when speech is in a language the product does not transcribe, from the detector's unrestricted answer.
import UttrflowCore

/// The refusal rule for speech in a language outside the transcribed set. See `Docs/latin-output.md`.
enum UnsupportedLanguageRefusal {
    /// The detector's probability at or above which its answer is certain enough to refuse on.
    static let minimumProbability = 0.95

    /// Languages the detector names for speech in a transcribed one, so naming them is not a foreign language.
    static let sameSpeech: Set<String> = ["ur"]

    /// The language to refuse, or `nil` when the speech is in a transcribed language or the detector is unsure.
    static func language(
        heard: LanguageCode, probability: Double, transcribed: [LanguageCode]
    ) -> LanguageCode? {
        guard probability >= minimumProbability, !transcribed.contains(heard),
            !sameSpeech.contains(heard.value)
        else { return nil }
        return heard
    }

    /// The language a Whisper language token such as `<|fr|>` names.
    static func language(ofToken token: String) -> LanguageCode? {
        guard token.hasPrefix("<|"), token.hasSuffix("|>") else { return nil }
        return LanguageCode(String(token.dropFirst(2).dropLast(2)))
    }
}

extension SpeechEngineError {
    /// The error a recogniser fault becomes: a refusal stays a refusal, anything else is a transcription failure.
    static func recognition(failedWith error: any Error) -> SpeechEngineError {
        if let refusal = error as? SpeechEngineError, case .unsupportedLanguage = refusal { return refusal }
        return .transcriptionFailed(description: error.localizedDescription)
    }
}
