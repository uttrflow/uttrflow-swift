public import UttrflowCore

/// A speech-recognition model the app can install.
///
/// Sizes are the real download, measured against the model repository rather than
/// estimated, because they are shown to the user before they commit to waiting.
public struct SpeechModel: Sendable, Hashable, Codable {
    /// Identifier used by the model repository.
    public let variant: String
    /// Total bytes fetched when installing.
    public let downloadBytes: Int64
    /// Whether it recognises languages other than English.
    public let isMultilingual: Bool
    /// The repository publishing the tokenizer this model decodes with.
    ///
    /// Named separately from ``variant`` because the two halves of an install come from
    /// different places: the weights are a converted CoreML build, while the vocabulary
    /// is only ever OpenAI's original. Recording it here is what lets the install fetch
    /// both, so the recogniser never has to reach for the network at the moment
    /// somebody speaks.
    public let tokenizerRepository: String

    public init(
        variant: String, downloadBytes: Int64, isMultilingual: Bool, tokenizerRepository: String
    ) {
        self.variant = variant
        self.downloadBytes = downloadBytes
        self.isMultilingual = isMultilingual
        self.tokenizerRepository = tokenizerRepository
    }
}

extension SpeechModel {
    /// What the app installs unless told otherwise.
    ///
    /// Multilingual, and the only listed model that copes with English and Hindi in
    /// one sentence. The turbo variant trades a little accuracy for roughly half the
    /// decode time, which matters more than the difference for dictation.
    public static let `default` = largeV3Turbo

    /// The turbo build is a distilled decoder over large-v3's encoder, and shares its
    /// vocabulary — which is why WhisperKit resolves it to the same tokenizer.
    public static let largeV3Turbo = SpeechModel(
        variant: "openai_whisper-large-v3-v20240930_turbo_632MB",
        downloadBytes: 645_668_913,
        isMultilingual: true,
        tokenizerRepository: "openai/whisper-large-v3"
    )

    public static let small = SpeechModel(
        variant: "openai_whisper-small",
        downloadBytes: 486_487_465,
        isMultilingual: true,
        tokenizerRepository: "openai/whisper-small"
    )

    /// Fastest and least accurate. Present so the benchmark has a floor to compare
    /// against, not because it is expected to be chosen.
    public static let base = SpeechModel(
        variant: "openai_whisper-base",
        downloadBytes: 146_719_453,
        isMultilingual: true,
        tokenizerRepository: "openai/whisper-base"
    )

    /// Every model the app knows how to install, smallest first.
    public static let catalogue: [SpeechModel] = [base, small, largeV3Turbo]

    /// Looks a model up by repository identifier.
    public static func named(_ variant: String) -> SpeechModel? {
        catalogue.first { $0.variant == variant }
    }

    /// Whether this model can be trusted with a given language.
    public func supports(_ language: LanguageCode) -> Bool {
        isMultilingual || language == .english
    }
}
