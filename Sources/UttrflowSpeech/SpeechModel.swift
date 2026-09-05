public import UttrflowCore

/// A speech-recognition model the app can install; sizes are the real download, shown before the wait.
public struct SpeechModel: Sendable, Hashable, Codable {
    /// Identifier used by the model repository.
    public let variant: String
    /// Total bytes fetched when installing.
    public let downloadBytes: Int64
    /// Whether it recognises languages other than English.
    public let isMultilingual: Bool
    /// The repository publishing the tokenizer, which is OpenAI's while the weights are a CoreML build.
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
    /// What the app installs unless told otherwise: multilingual, and half the decode time of large-v3.
    public static let `default` = largeV3Turbo

    /// A distilled decoder over large-v3's encoder, sharing its vocabulary and therefore its tokenizer.
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

    /// Fastest and least accurate, present as a floor for the benchmark rather than a choice.
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
