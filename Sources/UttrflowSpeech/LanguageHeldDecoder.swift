// Language detection held to the languages the product transcribes, and a decode judged by its language.
import CoreML
import UttrflowCore
import WhisperKit

/// Chooses the likeliest of the allowed language tokens, at any temperature. See `Docs/speech-engines.md`.
struct AllowedLanguageSampler: TokenSampling {
    /// The language tokens detection may answer with, in the order a tie is broken.
    let allowedTokens: [Int]

    /// The allowed language token with the highest logit, appended with its probability among the allowed ones.
    func update(tokens: [Int], logits: MLMultiArray, logProbs: [Float]) async -> SamplingResult {
        let scores = allowedTokens.map { logits[[0, 0, $0] as [NSNumber]].floatValue }
        guard let best = scores.indices.max(by: { scores[$0] < scores[$1] }) else {
            return SamplingResult(tokens: tokens, logProbs: logProbs, completed: true)
        }
        return SamplingResult(
            tokens: tokens + [allowedTokens[best]],
            logProbs: logProbs + [Self.logSoftmax(scores)[best]],
            completed: false)
    }

    func finalize(tokens: [Int], logProbs: [Float]) -> SamplingResult {
        SamplingResult(tokens: tokens, logProbs: logProbs, completed: true)
    }

    /// Each score's log-probability among `scores` alone, shifted by the largest so no exponent overflows.
    static func logSoftmax(_ scores: [Float]) -> [Float] {
        guard let top = scores.max() else { return [] }
        let normaliser = top + log(scores.reduce(0) { $0 + exp($1 - top) })
        return scores.map { $0 - normaliser }
    }

    /// The token ids of `languages` the tokenizer knows as language tokens, in their given order.
    static func tokens(
        for languages: [LanguageCode], among languageTokens: Set<Int>, lookUp: (String) -> Int?
    ) -> [Int] {
        languages.compactMap { lookUp("<|\($0.value)|>") }.filter { languageTokens.contains($0) }
    }
}

/// A text decoder whose language detection is held to `languages`; everything else is the wrapped decoder's.
final class LanguageHeldDecoder: TextDecoding {
    /// Each transcribed language's compression-ratio decision; `nil` keeps Whisper's 2.4. See `Docs/speech-engines.md`.
    static let compressionRatioThresholds: [String: Float?] = ["en": nil, "hi": 3.0]

    /// The reason WhisperKit names a compression fallback by, a raw string that `WhisperKitContractTests` pins.
    static let compressionFallbackReason = "compressionRatioThreshold"

    /// The fallback WhisperKit decided on, re-judged with the language's own compression-ratio threshold.
    static func judged(_ result: DecodingResult, options: DecodingOptions) -> DecodingFallback? {
        guard let fallback = result.fallback, fallback.fallbackReason == compressionFallbackReason,
            let language = options.language, let threshold = compressionRatioThresholds[language] ?? nil
        else { return result.fallback }
        var relaxed = options
        relaxed.compressionRatioThreshold = threshold
        // A compression verdict means the first-token check has already passed.
        return DecodingFallback(
            options: relaxed, isFirstTokenLogProbTooLow: false, noSpeechProb: result.noSpeechProb,
            compressionRatio: result.compressionRatio, avgLogProb: result.avgLogProb)
    }

    private var inner: any TextDecoding
    private let languages: [LanguageCode]

    init(wrapping inner: any TextDecoding, languages: [LanguageCode]) {
        self.inner = inner
        self.languages = languages
    }

    /// Detects among the allowed languages greedily, ignoring the fallback temperature it is handed.
    func detectLanguage(
        from encoderOutput: any AudioEncoderOutputType,
        using decoderInputs: any DecodingInputsType,
        sampler tokenSampler: any TokenSampling,
        options: DecodingOptions,
        temperature: FloatType
    ) async throws -> DecodingResult {
        let allowed = tokenizer.map { tokenizer in
            AllowedLanguageSampler.tokens(
                for: languages, among: tokenizer.allLanguageTokens,
                lookUp: tokenizer.convertTokenToId)
        }
        // A tokenizer that knows none of them detects as WhisperKit would, rather than not at all.
        guard let allowed, !allowed.isEmpty else {
            return try await inner.detectLanguage(
                from: encoderOutput, using: decoderInputs, sampler: tokenSampler,
                options: options, temperature: temperature)
        }
        return try await inner.detectLanguage(
            from: encoderOutput, using: decoderInputs,
            sampler: AllowedLanguageSampler(allowedTokens: allowed), options: options,
            temperature: 0)
    }

    var tokenizer: (any WhisperTokenizer)? {
        get { inner.tokenizer }
        set { inner.tokenizer = newValue }
    }

    var isModelMultilingual: Bool {
        get { inner.isModelMultilingual }
        set { inner.isModelMultilingual = newValue }
    }

    var logitsFilters: [any LogitsFiltering]? {
        get { inner.logitsFilters }
        set { inner.logitsFilters = newValue }
    }

    var supportsWordTimestamps: Bool { inner.supportsWordTimestamps }
    var logitsSize: Int? { inner.logitsSize }
    var kvCacheEmbedDim: Int? { inner.kvCacheEmbedDim }
    var kvCacheMaxSequenceLength: Int? { inner.kvCacheMaxSequenceLength }
    var windowSize: Int? { inner.windowSize }
    var embedSize: Int? { inner.embedSize }

    func predictLogits(_ inputs: any TextDecoderInputType) async throws -> (any TextDecoderOutputType)? {
        try await inner.predictLogits(inputs)
    }

    func prepareDecoderInputs(withPrompt initialPrompt: [Int]) throws -> any DecodingInputsType {
        try inner.prepareDecoderInputs(withPrompt: initialPrompt)
    }

    func prefillDecoderInputs(
        _ decoderInputs: any DecodingInputsType, withOptions options: DecodingOptions?
    ) async throws -> any DecodingInputsType {
        try await inner.prefillDecoderInputs(decoderInputs, withOptions: options)
    }

    func decodeText(
        from encoderOutput: any AudioEncoderOutputType,
        using decoderInputs: any DecodingInputsType,
        sampler tokenSampler: any TokenSampling,
        options decoderOptions: DecodingOptions,
        callback: TranscriptionCallback?
    ) async throws -> DecodingResult {
        let evidence = EvidenceSampler(wrapping: tokenSampler)
        var result = try await inner.decodeText(
            from: encoderOutput, using: decoderInputs, sampler: evidence,
            options: decoderOptions, callback: callback)
        result.tokenLogProbs = evidence.tokenLogProbs(of: result)
        // WhisperKit reads the temperature off a greedy sampler only, so the wrapper hides it; restored as it rounds it.
        if let greedy = tokenSampler as? GreedyTokenSampler {
            result.temperature = (Float(greedy.temperature) * 1000).rounded() / 1000
        }
        result.fallback = Self.judged(result, options: decoderOptions)
        return result
    }
}
