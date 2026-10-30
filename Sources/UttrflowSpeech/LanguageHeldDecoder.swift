// Language detection held to the languages the product transcribes, and a decode judged by its language.
import CoreML
import Foundation
import Synchronization
import UttrflowCore
import UttrflowDictionary
import WhisperKit

/// Chooses the likeliest of the allowed language tokens, at any temperature. See `Docs/speech-engines.md`.
struct AllowedLanguageSampler: TokenSampling {
    /// The language tokens detection may answer with, in the order a tie is broken.
    let allowedTokens: [Int]
    /// Every language token the model has, whose likeliest the sampler reads without letting it decide.
    var languageTokens: [Int] = []
    /// What the model answers when detection is not held.
    let unrestricted = UnrestrictedLanguage()

    /// The allowed language token with the highest logit, appended with its probability among the allowed ones.
    func update(tokens: [Int], logits: MLMultiArray, logProbs: [Float]) async -> SamplingResult {
        unrestricted.observe(
            languageTokens, scores: languageTokens.map { logits[[0, 0, $0] as [NSNumber]].floatValue })
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

/// The likeliest language token among all of them, and its probability among all of them.
final class UnrestrictedLanguage: Sendable {
    /// The likeliest token and its probability.
    struct Choice: Equatable {
        let token: Int
        let probability: Double
    }

    private let observed = Mutex<Choice?>(nil)

    /// The last observation, or `nil` when there is none.
    var choice: Choice? { observed.withLock { $0 } }

    /// Records the likeliest of `tokens` given their `scores`, or forgets the last when there are none.
    func observe(_ tokens: [Int], scores: [Float]) {
        let best = scores.indices.max { scores[$0] < scores[$1] }
        let probabilities = AllowedLanguageSampler.logSoftmax(scores)
        observed.withLock {
            $0 = best.map { Choice(token: tokens[$0], probability: Double(exp(probabilities[$0]))) }
        }
    }
}

/// A text decoder whose detection is held to `languages` and whose window decode is a `DecodeSession`.
final class LanguageHeldDecoder: TextDecoding {
    /// Each transcribed language's compression-ratio decision; `nil` keeps Whisper's 2.4. See `Docs/speech-engines.md`.
    static let compressionRatioThresholds: [String: Float?] = ["en": nil, "hi": 3.0]

    /// The reason WhisperKit names a compression fallback by, a raw string that `WhisperKitContractTests` pins.
    static let compressionFallbackReason = "compressionRatioThreshold"

    /// The reason WhisperKit names a silence verdict by; a silent window is final and is never retried warmer.
    static let silenceFallbackReason = "silence"

    /// The fallback WhisperKit decided on, silence first, a compression verdict re-judged per language.
    static func judged(_ result: DecodingResult, options: DecodingOptions) -> DecodingFallback? {
        // Whisper puts silence first; WhisperKit checks the first token before it, and the warm retry invents text.
        if let threshold = options.noSpeechThreshold, result.noSpeechProb > threshold {
            return DecodingFallback(needsFallback: false, fallbackReason: silenceFallbackReason)
        }
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

    /// The greedy decode instead of a warmer retry that drops a romanised Hindi word it held; Hindi is romanised, never translated.
    static func untranslated(_ warm: DecodingResult, greedy: DecodingResult?) -> DecodingResult {
        guard let greedy else { return warm }
        let held = hindiWords(in: greedy.text)
        // One Hindi-looking word is no sign of Hinglish, so a retry that drops it may have heard it right.
        guard held.count >= 2, !held.isSubset(of: hindiWords(in: warm.text)) else { return warm }
        var kept = greedy
        kept.fallback = nil
        return kept
    }

    /// The distinct romanised Hindi words of a transcript that no English word is spelled as.
    private static func hindiWords(in text: String) -> Set<String> {
        Set(
            WordTokens.words(text, .display).map { WordShape($0).core.lowercased() }.filter {
                LoanwordRestoration.isRomanisedHindi($0) && !LexicalClass.isKnownEnglishWord($0)
            })
    }

    private var inner: any TextDecoding
    private let languages: [LanguageCode]
    /// Every decode window's per-step entropy, one record per `decodeText` call, fallback retries included.
    let windows: DecodeWindowLog
    /// Prefill time, prompt steps and timestamp steps since the last `drainSplit`, which WhisperKit's timings omit.
    private let split = Mutex(RecognitionTimings.zero)
    /// The untranscribed language the last detection is certain of, which the next decode refuses.
    private let refusal = Mutex<LanguageCode?>(nil)
    /// The current window's greedy decode, which a warmer retry that translates its Hindi gives way to.
    private var greedy: DecodingResult?

    init(
        wrapping inner: any TextDecoding, languages: [LanguageCode],
        windows: DecodeWindowLog = DecodeWindowLog()
    ) {
        self.inner = inner
        self.languages = languages
        self.windows = windows
    }

    /// The split recorded since the last drain, leaving it and any unread refusal empty for the next piece.
    func drainSplit() -> RecognitionTimings {
        refusal.withLock { $0 = nil }
        return split.withLock { recorded in
            defer { recorded = .zero }
            return recorded
        }
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
        refusal.withLock { $0 = nil }
        // A tokenizer that knows none of them detects as WhisperKit would, rather than not at all.
        guard let allowed, !allowed.isEmpty else {
            return try await inner.detectLanguage(
                from: encoderOutput, using: decoderInputs, sampler: tokenSampler,
                options: options, temperature: temperature)
        }
        let sampler = AllowedLanguageSampler(
            allowedTokens: allowed, languageTokens: tokenizer?.allLanguageTokens.sorted() ?? [])
        let detected = try await inner.detectLanguage(
            from: encoderOutput, using: decoderInputs, sampler: sampler, options: options, temperature: 0)
        refusal.withLock { $0 = refused(sampler.unrestricted.choice) }
        return detected
    }

    /// The untranscribed language the model is certain of, if any.
    private func refused(_ choice: UnrestrictedLanguage.Choice?) -> LanguageCode? {
        guard let choice, let token = tokenizer?.convertIdToToken(choice.token),
            let heard = UnsupportedLanguageRefusal.language(ofToken: token)
        else { return nil }
        return UnsupportedLanguageRefusal.language(
            heard: heard, probability: choice.probability, transcribed: languages)
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
        let start = Date()
        defer {
            let seconds = Date().timeIntervalSince(start)
            split.withLock { $0 = $0.adding(RecognitionTimings(prefillSeconds: seconds)) }
        }
        return try await inner.prefillDecoderInputs(decoderInputs, withOptions: options)
    }

    func decodeText(
        from encoderOutput: any AudioEncoderOutputType,
        using decoderInputs: any DecodingInputsType,
        sampler tokenSampler: any TokenSampling,
        options decoderOptions: DecodingOptions,
        callback: TranscriptionCallback?
    ) async throws -> DecodingResult {
        // Taken, so the refusal ends this window's decode and is never read again.
        if let language = refusal.withLock({ $0.take() }) {
            throw SpeechEngineError.unsupportedLanguage(language)
        }
        // The same filter list WhisperKit reads for this decode, so the record undoes exactly the bias applied.
        let bias = inner.logitsFilters?.lazy.compactMap { $0 as? PhraseBiasFilter }.first
        let session = try DecodeSession(
            decoder: inner,
            window: .init(encoderOutput: encoderOutput, inputs: decoderInputs, options: decoderOptions))
        // The wrappers hide a greedy sampler's temperature, so it is read off the sampler handed in.
        let temperature = DecodeSession.temperature(of: tokenSampler, options: decoderOptions)
        let sampler = SeededFallbackSampler.replacing(
            tokenSampler, temperature: temperature, options: decoderOptions,
            endToken: session.tokenizer.specialTokens.endToken)
        let evidence = EvidenceSampler(wrapping: sampler, bias: bias)
        var (result, stepSplit) = try await session.decodeSplit(sampler: evidence, callback: callback)
        split.withLock { $0 = $0.adding(stepSplit) }
        result.tokenLogProbs = evidence.tokenLogProbs(of: result)
        result.temperature = temperature
        result.fallback = Self.judged(result, options: decoderOptions)
        windows.append(evidence.window(of: result))
        guard temperature > 0 else {
            greedy = result
            return result
        }
        return Self.untranslated(result, greedy: greedy)
    }
}
