// Holds detection to the transcribed languages and judges a decode by the language it was decoded in.
import CoreML
import Testing
import UttrflowCore
import WhisperKit

@testable import UttrflowSpeech

/// Detection answers only in a transcribed language, and answers the same way every time.
@Suite("The language-held decoder")
struct LanguageHeldDecoderTests {
    /// Language token ids in a fixture vocabulary, with Urdu the one the product does not transcribe.
    static let english = 10
    static let hindi = 11
    static let urdu = 12
    static let french = 13
    static let vocabularySize = 16

    /// Half-precision logits after WhisperKit's language filter: every token but a language is minus infinity.
    static func logits(_ scores: [Int: Float]) throws -> MLMultiArray {
        let logits = try MLMultiArray(shape: [1, 1, NSNumber(value: vocabularySize)], dataType: .float16)
        for index in 0..<vocabularySize {
            logits[[0, 0, index] as [NSNumber]] = NSNumber(value: scores[index] ?? -Float.infinity)
        }
        return logits
    }

    /// Hindi speech as the model sometimes hears it: Urdu first, Hindi a close second.
    static func urduFirst() throws -> MLMultiArray {
        try logits([urdu: 4.0, hindi: 3.8, english: 1.0])
    }

    // MARK: The sampler

    @Test("answers Hindi when Urdu scores highest but only English and Hindi are allowed")
    func refusesUrdu() async throws {
        let sampler = AllowedLanguageSampler(allowedTokens: [Self.english, Self.hindi])

        let result = await sampler.update(tokens: [1], logits: try Self.urduFirst(), logProbs: [0])

        #expect(result.tokens == [1, Self.hindi])
        #expect(result.logProbs.count == result.tokens.count)
        #expect(!result.completed)
    }

    @Test("answers English for English speech")
    func keepsEnglish() async throws {
        let sampler = AllowedLanguageSampler(allowedTokens: [Self.english, Self.hindi])
        let logits = try Self.logits([Self.english: 6, Self.hindi: 2, Self.urdu: 1])

        let result = await sampler.update(tokens: [1], logits: logits, logProbs: [0])

        #expect(result.tokens.last == Self.english)
    }

    @Test("reports the chosen language's probability among the allowed ones")
    func probabilityIsAmongTheAllowed() async throws {
        let sampler = AllowedLanguageSampler(allowedTokens: [Self.english, Self.hindi])
        let logits = try Self.logits([Self.english: 0, Self.hindi: 0, Self.urdu: 9])

        let result = await sampler.update(tokens: [1], logits: logits, logProbs: [0])

        #expect(abs((result.logProbs.last ?? 0) - log(0.5)) < 1e-5)
    }

    @Test("with nothing allowed, appends nothing and stops")
    func nothingAllowed() async throws {
        let result = await AllowedLanguageSampler(allowedTokens: [])
            .update(tokens: [1], logits: try Self.urduFirst(), logProbs: [0])

        #expect(result.tokens == [1])
        #expect(result.completed)
        #expect(AllowedLanguageSampler(allowedTokens: []).finalize(tokens: [1], logProbs: [0]).completed)
    }

    @Test("log-probabilities over large scores stay finite and sum to one")
    func logSoftmaxIsStable() {
        let logProbs = AllowedLanguageSampler.logSoftmax([1000, 999, 998])

        #expect(logProbs.allSatisfy { $0.isFinite })
        #expect(abs(logProbs.map { exp($0) }.reduce(0, +) - 1) < 1e-4)
        #expect(AllowedLanguageSampler.logSoftmax([]).isEmpty)
    }

    @Test("finds the transcribed languages' tokens, in order, skipping any the tokenizer lacks")
    func tokensForLanguages() {
        let ids = ["<|en|>": Self.english, "<|hi|>": Self.hindi, "<|xx|>": 3]
        let languages = [LanguageCode.hindi, .english, LanguageCode("xx"), LanguageCode("fr")].compactMap(
            \.self)

        let tokens = AllowedLanguageSampler.tokens(
            for: languages, among: [Self.english, Self.hindi, Self.urdu], lookUp: { ids[$0] })

        #expect(tokens == [Self.hindi, Self.english])
    }

    // MARK: What the model would have answered

    @Test("reads the likeliest language of all of them without letting it decide")
    func readsTheUnrestrictedChoice() async throws {
        let sampler = AllowedLanguageSampler(
            allowedTokens: [Self.english, Self.hindi],
            languageTokens: [Self.english, Self.hindi, Self.urdu, Self.french])
        let logits = try Self.logits([Self.english: 1, Self.hindi: 0, Self.urdu: 0, Self.french: 9])

        let result = await sampler.update(tokens: [1], logits: logits, logProbs: [0])

        #expect(result.tokens.last == Self.english)
        #expect(sampler.unrestricted.choice?.token == Self.french)
        #expect((sampler.unrestricted.choice?.probability ?? 0) > 0.99)
    }

    @Test("reads nothing when it is told no language tokens")
    func readsNothingWithoutTokens() async throws {
        let sampler = AllowedLanguageSampler(allowedTokens: [Self.english, Self.hindi])

        _ = await sampler.update(tokens: [1], logits: try Self.urduFirst(), logProbs: [0])

        #expect(sampler.unrestricted.choice == nil)
    }

    // MARK: Refusing a language the product does not transcribe

    /// A decoder whose detection hears `scores` and whose decode is scripted, as WhisperKit drives them.
    static func decoder(hearing scores: [Int: Float]) throws -> LanguageHeldDecoder {
        let inner = FakeTextDecoder(logits: try logits(scores), tokenizer: FakeLanguageTokenizer())
        return LanguageHeldDecoder(wrapping: inner, languages: LanguageCode.transcribed)
    }

    /// What a window's decode throws after `decoder` detected `scores`, or `nil` when it ran.
    static func decodeAfterDetecting(_ scores: [Int: Float]) async throws -> SpeechEngineError? {
        let decoder = try decoder(hearing: scores)
        let options = VocabularyPrompt.decodingOptions(languageHint: nil)
        _ = try await decoder.detectLanguage(
            from: try Self.logits(scores), using: FakeDecodingInputs(),
            sampler: GreedyTokenSampler(temperature: 0, eotToken: 0, decodingOptions: options),
            options: options, temperature: 0)
        do {
            _ = try await decoder.decodeText(
                from: try Self.logits(scores), using: FakeDecodingInputs(),
                sampler: GreedyTokenSampler(temperature: 0, eotToken: 0, decodingOptions: options),
                options: options, callback: nil)
            return nil
        } catch let error as SpeechEngineError {
            return error
        } catch {
            return nil
        }
    }

    @Test("refuses the decode of speech the model is certain is French")
    func refusesFrench() async throws {
        let refused = try await Self.decodeAfterDetecting([Self.french: 20, Self.english: 3, Self.hindi: 1])

        #expect(refused == .unsupportedLanguage(try #require(LanguageCode("fr"))))
    }

    @Test("lets Hindi through when the model hears Urdu")
    func keepsHindiHeardAsUrdu() async throws {
        let refused = try await Self.decodeAfterDetecting([Self.urdu: 20, Self.hindi: 3, Self.english: 1])

        #expect(refused == nil)
    }

    @Test("lets English and Hindi through")
    func keepsTranscribedLanguages() async throws {
        #expect(try await Self.decodeAfterDetecting([Self.english: 20, Self.french: 3]) == nil)
        #expect(try await Self.decodeAfterDetecting([Self.hindi: 20, Self.french: 3]) == nil)
    }

    @Test("lets speech through when the model is unsure it is French")
    func keepsUnsureFrench() async throws {
        #expect(
            try await Self.decodeAfterDetecting([Self.french: 3, Self.english: 2.5, Self.hindi: 0]) == nil)
    }

    @Test("refuses one window only, so the next detection starts clean")
    func refusalIsTaken() async throws {
        let scores: [Int: Float] = [Self.french: 20, Self.english: 3]
        let decoder = try Self.decoder(hearing: scores)
        let options = VocabularyPrompt.decodingOptions(languageHint: nil)
        let sampler = GreedyTokenSampler(temperature: 0, eotToken: 0, decodingOptions: options)
        _ = try await decoder.detectLanguage(
            from: try Self.logits(scores), using: FakeDecodingInputs(), sampler: sampler, options: options,
            temperature: 0)

        _ = try? await decoder.decodeText(
            from: try Self.logits(scores), using: FakeDecodingInputs(), sampler: sampler, options: options,
            callback: nil)

        // The inner fake cannot decode, so a second decode throws WhisperKit's error, not the refusal.
        await #expect(throws: WhisperError.self) {
            try await decoder.decodeText(
                from: try Self.logits(scores), using: FakeDecodingInputs(), sampler: sampler,
                options: options,
                callback: nil)
        }
    }

    @Test("forgets an unread refusal when the next piece begins")
    func drainForgetsTheRefusal() async throws {
        let scores: [Int: Float] = [Self.french: 20, Self.english: 3]
        let decoder = try Self.decoder(hearing: scores)
        let options = VocabularyPrompt.decodingOptions(languageHint: nil)
        let sampler = GreedyTokenSampler(temperature: 0, eotToken: 0, decodingOptions: options)
        _ = try await decoder.detectLanguage(
            from: try Self.logits(scores), using: FakeDecodingInputs(), sampler: sampler, options: options,
            temperature: 0)

        _ = decoder.drainSplit()

        await #expect(throws: WhisperError.self) {
            try await decoder.decodeText(
                from: try Self.logits(scores), using: FakeDecodingInputs(), sampler: sampler,
                options: options,
                callback: nil)
        }
    }

    // MARK: The decoder

    @Test("detects Hindi, never Urdu, on every fallback temperature WhisperKit hands it")
    func detectionIsHeldAtEveryTemperature() async throws {
        let inner = FakeTextDecoder(logits: try Self.urduFirst(), tokenizer: FakeLanguageTokenizer())
        let decoder = LanguageHeldDecoder(wrapping: inner, languages: LanguageCode.transcribed)

        var answers: Set<String> = []
        for temperature in stride(from: Float(0), through: 1.0, by: 0.2) {
            for _ in 0..<20 {
                let sampler = GreedyTokenSampler(
                    temperature: FloatType(temperature), eotToken: 0,
                    decodingOptions: VocabularyPrompt.decodingOptions(languageHint: nil))
                let result = try await decoder.detectLanguage(
                    from: try Self.urduFirst(), using: FakeDecodingInputs(), sampler: sampler,
                    options: VocabularyPrompt.decodingOptions(languageHint: nil),
                    temperature: FloatType(temperature))
                answers.insert(result.language)
            }
        }

        #expect(answers == ["hi"])
        #expect(inner.temperatures.allSatisfy { $0 == 0 })
    }

    @Test("without a tokenizer, detects with the sampler and temperature it was handed")
    func noTokenizerDetectsAsWhisperKitWould() async throws {
        let inner = FakeTextDecoder(logits: try Self.urduFirst(), tokenizer: nil)
        let decoder = LanguageHeldDecoder(wrapping: inner, languages: LanguageCode.transcribed)
        let sampler = GreedyTokenSampler(
            temperature: 0, eotToken: 0,
            decodingOptions: VocabularyPrompt.decodingOptions(languageHint: nil))

        _ = try await decoder.detectLanguage(
            from: try Self.urduFirst(), using: FakeDecodingInputs(), sampler: sampler,
            options: VocabularyPrompt.decodingOptions(languageHint: nil), temperature: 0.4)

        #expect(inner.samplers.last is GreedyTokenSampler)
        #expect(inner.temperatures == [0.4])
    }

    @Test("passes everything but detection straight to the decoder it wraps")
    func forwardsTheRest() async throws {
        let inner = FakeTextDecoder(logits: try Self.urduFirst(), tokenizer: nil)
        let decoder = LanguageHeldDecoder(wrapping: inner, languages: LanguageCode.transcribed)
        let options = VocabularyPrompt.decodingOptions(languageHint: nil)

        decoder.isModelMultilingual = true
        decoder.logitsFilters = []
        decoder.tokenizer = nil
        let inputs = try decoder.prepareDecoderInputs(withPrompt: [1])
        _ = try await decoder.prefillDecoderInputs(inputs, withOptions: options)
        _ = try await decoder.predictLogits(try Self.urduFirst())

        #expect(inner.isModelMultilingual && decoder.isModelMultilingual)
        #expect(decoder.logitsFilters?.isEmpty == true)
        #expect(decoder.tokenizer == nil)
        #expect(decoder.supportsWordTimestamps)
        #expect(decoder.logitsSize == Self.vocabularySize)
        #expect(
            [
                decoder.kvCacheEmbedDim, decoder.kvCacheMaxSequenceLength, decoder.windowSize,
                decoder.embedSize,
            ] == [1, 2, 3, 4])
        #expect(inner.calls == ["prepare", "prefill", "predict"])
    }

    // MARK: Judging a decode

    /// A decode as WhisperKit judges it with the product's options, in `language`.
    static func decoded(
        _ language: String, compressionRatio: Float, avgLogProb: Float
    ) -> (DecodingResult, DecodingOptions) {
        var options = VocabularyPrompt.decodingOptions(languageHint: nil)
        options.language = language
        let fallback = DecodingFallback(
            options: options, isFirstTokenLogProbTooLow: false, noSpeechProb: 0,
            compressionRatio: compressionRatio, avgLogProb: avgLogProb)
        let result = FakeTextDecoder.result(
            language: language, compressionRatio: compressionRatio, avgLogProb: avgLogProb,
            fallback: fallback)
        return (result, options)
    }

    @Test("WhisperKit names a compression-ratio rejection the way the judge reads it")
    func compressionReasonIsTheOneRead() {
        let (result, _) = Self.decoded("hi", compressionRatio: 2.44, avgLogProb: -0.05)

        #expect(result.fallback?.fallbackReason == "compressionRatioThreshold")
        #expect(result.fallback?.needsFallback == true)
    }

    @Test("accepts a confident Devanagari decode that Whisper's 2.4 would retry warmer")
    func acceptsCleanHindi() {
        let (result, options) = Self.decoded("hi", compressionRatio: 2.6, avgLogProb: -0.05)

        #expect(LanguageHeldDecoder.judged(result, options: options) == nil)
    }

    @Test("still retries a Hindi decode that repeats itself")
    func retriesRepeatingHindi() {
        let (result, options) = Self.decoded("hi", compressionRatio: 3.9, avgLogProb: -0.05)

        #expect(
            LanguageHeldDecoder.judged(result, options: options)?.fallbackReason
                == "compressionRatioThreshold")
    }

    @Test("still retries a Hindi decode past compression that the model was unsure of")
    func retriesUnsureHindi() {
        let (result, options) = Self.decoded("hi", compressionRatio: 2.6, avgLogProb: -1.6)

        #expect(LanguageHeldDecoder.judged(result, options: options)?.fallbackReason == "logProbThreshold")
    }

    @Test("leaves an English decode to Whisper's own threshold")
    func englishIsUnchanged() {
        let (result, options) = Self.decoded("en", compressionRatio: 2.6, avgLogProb: -0.05)

        #expect(
            LanguageHeldDecoder.judged(result, options: options)?.fallbackReason
                == "compressionRatioThreshold")
    }

    @Test("a silence verdict outranks a first-token rejection and ends the retries")
    func silenceOutranksFirstToken() {
        var options = VocabularyPrompt.decodingOptions(languageHint: nil)
        options.language = "en"
        var result = FakeTextDecoder.result(
            language: "en", compressionRatio: 1.0,
            fallback: DecodingFallback(needsFallback: true, fallbackReason: "firstTokenLogProbThreshold"))
        result.noSpeechProb = 0.9

        let verdict = LanguageHeldDecoder.judged(result, options: options)

        #expect(verdict?.fallbackReason == "silence")
        #expect(verdict?.needsFallback == false)
    }

    @Test("a silence verdict outranks a compression rejection in either language")
    func silenceOutranksCompression() {
        for language in ["en", "hi"] {
            var (result, options) = Self.decoded(language, compressionRatio: 3.9, avgLogProb: -1.6)
            result.noSpeechProb = 0.9
            #expect(LanguageHeldDecoder.judged(result, options: options)?.needsFallback == false)
        }
    }

    @Test("a window below the no-speech threshold keeps its first-token retry")
    func speechKeepsItsRetry() {
        var options = VocabularyPrompt.decodingOptions(languageHint: nil)
        options.language = "en"
        var result = FakeTextDecoder.result(
            language: "en",
            fallback: DecodingFallback(needsFallback: true, fallbackReason: "firstTokenLogProbThreshold"))
        result.noSpeechProb = 0.2

        #expect(LanguageHeldDecoder.judged(result, options: options)?.needsFallback == true)
    }

    @Test("leaves any other verdict alone")
    func otherVerdictsAreUnchanged() {
        var options = VocabularyPrompt.decodingOptions(languageHint: .hindi)
        options.language = "hi"
        let firstToken = FakeTextDecoder.result(
            language: "hi", compressionRatio: 2.6,
            fallback: DecodingFallback(needsFallback: true, fallbackReason: "firstTokenLogProbThreshold"))

        #expect(
            LanguageHeldDecoder.judged(firstToken, options: options)?.fallbackReason
                == "firstTokenLogProbThreshold")
        #expect(LanguageHeldDecoder.judged(FakeTextDecoder.result(language: "hi"), options: options) == nil)
    }

    @Test("hands WhisperKit a decode already judged by its language")
    func decodeTextIsJudged() async throws {
        let scripted = ScriptedDecoder(script: [3: 5, 4: 50])
        let decoder = LanguageHeldDecoder(wrapping: scripted, languages: LanguageCode.transcribed)
        let options = DecodeSessionTests.options {
            $0.language = "hi"
            $0.compressionRatioThreshold = 0
        }

        let result = try await decoder.decodeText(
            from: try ScriptedDecoder.array([1, 3, 1, 1]),
            using: try decoder.prepareDecoderInputs(withPrompt: DecodeSessionTests.opening),
            sampler: GreedyTokenSampler(temperature: 0, eotToken: 50, decodingOptions: options),
            options: options, callback: nil)

        #expect(result.tokens == DecodeSessionTests.opening + [5, 50])
        #expect(result.fallback == nil)
    }

    @Test("reports the fallback temperature of the greedy sampler it wraps for evidence")
    func temperatureSurvivesTheWrap() async throws {
        let scripted = ScriptedDecoder(script: [3: 50])
        let decoder = LanguageHeldDecoder(wrapping: scripted, languages: LanguageCode.transcribed)
        let options = DecodeSessionTests.options()

        let result = try await decoder.decodeText(
            from: try ScriptedDecoder.array([1, 3, 1, 1]),
            using: try decoder.prepareDecoderInputs(withPrompt: DecodeSessionTests.opening),
            sampler: GreedyTokenSampler(temperature: 0.4, eotToken: 50, decodingOptions: options),
            options: options, callback: nil)

        #expect(result.temperature == 0.4)
    }

    @Test("decodes a fallback window the same way every time it is handed the same audio")
    func fallbackWindowRepeats() async throws {
        let options = DecodeSessionTests.options { $0.firstTokenLogProbThreshold = nil }
        var decodes: [[Int]] = []
        for _ in 0..<2 {
            let decoder = LanguageHeldDecoder(
                wrapping: ScriptedDecoder(script: [:], unscripted: nil), languages: LanguageCode.transcribed)
            let result = try await decoder.decodeText(
                from: try ScriptedDecoder.array([1, 3, 1, 1]),
                using: try decoder.prepareDecoderInputs(withPrompt: DecodeSessionTests.opening),
                sampler: GreedyTokenSampler(temperature: 1, eotToken: 50, decodingOptions: options),
                options: options, callback: nil)
            decodes.append(result.tokens)
        }

        #expect(decodes[0].count > DecodeSessionTests.opening.count + 8)
        #expect(decodes[0] == decodes[1])
    }

    // MARK: What is asked for

    @Test("transcribes, never translates, whether the language is detected or hinted")
    func alwaysTranscribes() {
        #expect(VocabularyPrompt.decodingOptions(languageHint: nil).task == .transcribe)
        #expect(VocabularyPrompt.decodingOptions(languageHint: .hindi).task == .transcribe)
    }

    @Test("the languages detection is held to are English and Hindi")
    func transcribedLanguages() {
        #expect(LanguageCode.transcribed == [.english, .hindi])
    }

    /// A transcribed language with no recorded decision would silently keep Whisper's threshold. See `Docs/adding-a-language.md`.
    @Test("records a compression-ratio decision for exactly the transcribed languages")
    func everyTranscribedLanguageHasACompressionDecision() {
        let transcribed = Set(LanguageCode.transcribed.map(\.value))
        #expect(Set(LanguageHeldDecoder.compressionRatioThresholds.keys) == transcribed)
    }
}

/// The inputs a decode is handed, of which these tests read nothing.
private struct FakeDecodingInputs: DecodingInputsType {
    var initialPrompt: [Int] = [1]
    var inputIds = (try? MLMultiArray(shape: [1], dataType: .int32)) ?? MLMultiArray()
    var cacheLength = (try? MLMultiArray(shape: [1], dataType: .int32)) ?? MLMultiArray()

    func reset(maxTokenContext: Int) {}
}

/// A decoder that detects the way WhisperKit's does: one step of fixed logits through the sampler it is given.
private final class FakeTextDecoder: TextDecoding {
    let logits: MLMultiArray
    var tokenizer: (any WhisperTokenizer)?
    var isModelMultilingual = false
    var logitsFilters: [any LogitsFiltering]?
    var supportsWordTimestamps: Bool { true }
    var logitsSize: Int? { LanguageHeldDecoderTests.vocabularySize }
    var kvCacheEmbedDim: Int? { 1 }
    var kvCacheMaxSequenceLength: Int? { 2 }
    var windowSize: Int? { 3 }
    var embedSize: Int? { 4 }
    private(set) var samplers: [any TokenSampling] = []
    private(set) var temperatures: [FloatType] = []
    private(set) var calls: [String] = []

    init(logits: MLMultiArray, tokenizer: (any WhisperTokenizer)?) {
        self.logits = logits
        self.tokenizer = tokenizer
    }

    func detectLanguage(
        from encoderOutput: any AudioEncoderOutputType, using decoderInputs: any DecodingInputsType,
        sampler tokenSampler: any TokenSampling, options: DecodingOptions, temperature: FloatType
    ) async throws -> DecodingResult {
        samplers.append(tokenSampler)
        temperatures.append(temperature)
        let sampled = await tokenSampler.update(tokens: [1], logits: logits, logProbs: [0])
        let names = [
            LanguageHeldDecoderTests.english: "en", LanguageHeldDecoderTests.hindi: "hi",
            LanguageHeldDecoderTests.urdu: "ur",
        ]
        return Self.result(language: sampled.tokens.last.flatMap { names[$0] } ?? "en")
    }

    func predictLogits(_ inputs: any TextDecoderInputType) async throws -> (any TextDecoderOutputType)? {
        calls.append("predict")
        return nil
    }

    func prepareDecoderInputs(withPrompt initialPrompt: [Int]) throws -> any DecodingInputsType {
        calls.append("prepare")
        return FakeDecodingInputs()
    }

    func prefillDecoderInputs(
        _ decoderInputs: any DecodingInputsType, withOptions options: DecodingOptions?
    ) async throws -> any DecodingInputsType {
        calls.append("prefill")
        return decoderInputs
    }

    func decodeText(
        from encoderOutput: any AudioEncoderOutputType, using decoderInputs: any DecodingInputsType,
        sampler tokenSampler: any TokenSampling, options decoderOptions: DecodingOptions,
        callback: TranscriptionCallback?
    ) async throws -> DecodingResult {
        throw WhisperError.decodingFailed("the language-held decoder decodes through its session")
    }

    static func result(
        language: String, compressionRatio: Float = 0, avgLogProb: Float = 0,
        fallback: DecodingFallback? = nil
    ) -> DecodingResult {
        DecodingResult(
            language: language, languageProbs: [:], tokens: [], tokenLogProbs: [], text: "",
            avgLogProb: avgLogProb, noSpeechProb: 0, temperature: 0,
            compressionRatio: compressionRatio, cache: nil, timings: TranscriptionTimings(),
            fallback: fallback)
    }
}

/// A tokenizer that knows three language tokens by name and nothing else.
private struct FakeLanguageTokenizer: WhisperTokenizer {
    private let ids = [
        "<|en|>": LanguageHeldDecoderTests.english, "<|hi|>": LanguageHeldDecoderTests.hindi,
        "<|ur|>": LanguageHeldDecoderTests.urdu, "<|fr|>": LanguageHeldDecoderTests.french,
    ]

    func encode(text: String) -> [Int] { [] }
    func decode(tokens: [Int]) -> String { "" }
    func convertTokenToId(_ token: String) -> Int? { ids[token] }
    func convertIdToToken(_ id: Int) -> String? { ids.first { $0.value == id }?.key }
    var specialTokens: SpecialTokens { DecoderPrefillTests.specialTokens }
    var allLanguageTokens: Set<Int> { Set(ids.values) }
    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) { ([], []) }
}
