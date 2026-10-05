public import UttrflowCore

/// Which languages Apple's model is asked to tidy, decided apart from the model so it can be tested.
public enum AppleModelLanguages {
    /// Languages Apple's model is never asked about, listed or not: it refuses most of their dictations. See Docs/ai-model-output.md.
    public static let withheld: Set<LanguageCode> = [.hindi]

    /// Available when Apple declares the language and it is not withheld; otherwise the next engine tidies it.
    public static func availability(
        of language: LanguageCode, declaredByApple: Bool
    ) -> TransformerAvailability {
        guard declaredByApple, !withheld.contains(language) else { return .unsupportedLanguage(language) }
        return .available
    }
}
