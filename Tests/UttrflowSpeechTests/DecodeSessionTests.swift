// The decode session steps a window as WhisperKit's loop does, against a decoder that answers from a script.
import CoreML
import Foundation
import Synchronization
import Testing
import WhisperKit

@testable import UttrflowSpeech

@Suite("The decode session")
struct DecodeSessionTests {
    static let special = DecoderPrefillTests.specialTokens
    /// Start of transcript, English, transcribe, no timestamps: the opening WhisperKit forces.
    static let opening = [51, 52, 53, 57]

    static func options(_ change: (inout DecodingOptions) -> Void = { _ in }) -> DecodingOptions {
        var options = DecodingOptions(
            language: "en", temperature: 0, usePrefillPrompt: true, skipSpecialTokens: true,
            withoutTimestamps: true, suppressBlank: false)
        change(&options)
        return options
    }

    static func decode(
        _ decoder: ScriptedDecoder, prompt: [Int] = opening, options: DecodingOptions = options(),
        callback: TranscriptionCallback? = nil
    ) async throws -> DecodingResult {
        let inputs = try decoder.prepareDecoderInputs(withPrompt: prompt)
        let session = try DecodeSession(
            decoder: decoder,
            window: .init(
                encoderOutput: try ScriptedDecoder.array([1, 3, 1, 1]), inputs: inputs, options: options))
        return try await session.decode(
            sampler: GreedyTokenSampler(temperature: 0, eotToken: special.endToken, decodingOptions: options),
            callback: callback)
    }

    @Test("forces the prompt, then keeps each greedy token until the end token")
    func decodesGreedily() async throws {
        let decoder = ScriptedDecoder(script: [3: 5, 4: 6, 5: 50])

        let result = try await Self.decode(decoder)

        #expect(result.tokens == Self.opening + [5, 6, 50])
        #expect(result.tokenLogProbs.count == result.tokens.count)
        #expect(decoder.fed == Self.opening + [5, 6])
        #expect(result.text == "51 52 53 57 5 6 50")
        #expect(result.language == "en")
        #expect(result.temperature == 0)
        #expect(result.cache?.alignmentWeights != nil)
        #expect(result.timings?.totalDecodingLoops == 6)
    }

    @Test("ignores an end token sampled while the prompt is still being forced")
    func prefillEndIsIgnored() async throws {
        let result = try await Self.decode(ScriptedDecoder(script: [0: 50, 1: 50, 3: 5, 4: 50]))

        #expect(result.tokens == Self.opening + [5, 50])
    }

    @Test("stops at the first sampled token when its log-probability is under the threshold")
    func firstTokenThreshold() async throws {
        let options = Self.options { $0.firstTokenLogProbThreshold = 1 }

        let result = try await Self.decode(ScriptedDecoder(script: [3: 5]), options: options)

        #expect(result.tokens == Self.opening + [Self.special.endToken])
        #expect(result.fallback?.fallbackReason == "firstTokenLogProbThreshold")
    }

    @Test("reads the language off the decoded tokens when none was asked for")
    func languageFromTokens() async throws {
        let options = Self.options { $0.language = nil }

        let result = try await Self.decode(ScriptedDecoder(script: [3: 50]), options: options)

        #expect(result.language == "52")
        #expect(result.languageProbs["52"] == 0)
    }

    @Test("falls back to English when no language was asked for or decoded")
    func languageDefault() async throws {
        let options = Self.options { $0.language = nil }

        let result = try await Self.decode(ScriptedDecoder(script: [1: 50]), prompt: [51], options: options)

        #expect(result.language == "en")
    }

    @Test("lets a timestamp the model chose stand where the prompt ends on one")
    func lastPrefillTimestamp() async throws {
        let decoder = ScriptedDecoder(script: [2: 60, 3: 50])

        let result = try await Self.decode(decoder, prompt: [51, 52, 53, 58])

        #expect(decoder.fed == [51, 52, 53, 60])
        #expect(result.tokens.prefix(4) == [51, 52, 53, 60])
    }

    @Test("applies the suppression and timestamp rules the options ask for")
    func rulesApply() async throws {
        let options = Self.options {
            $0.withoutTimestamps = false
            $0.suppressBlank = true
            $0.suppressTokens = [5, 50]
            $0.maxInitialTimestamp = 0.02
        }

        let result = try await Self.decode(ScriptedDecoder(script: [3: 5]), options: options)

        #expect(!result.tokens.dropFirst(4).contains(5))
    }

    @Test("stops when the progress callback answers false past the prefill")
    func callbackStops() async throws {
        let reported = Mutex(0)
        let decoder = ScriptedDecoder(script: [:], delay: .milliseconds(20))

        let result = try await Self.decode(decoder) { progress in
            reported.withLock { $0 += 1 }
            return progress.tokens.count < 5
        }

        #expect(reported.withLock { $0 } > 0)
        #expect(result.tokens.count < 40)
    }

    @Test("refuses a window WhisperKit's loop would refuse")
    func refusals() throws {
        let options = Self.options()
        let encoder = try ScriptedDecoder.array([1, 3, 1, 1])
        let decoder = ScriptedDecoder(script: [:])
        let inputs = try decoder.prepareDecoderInputs(withPrompt: Self.opening)
        let windows: [DecodeSession.Window] = [
            .init(
                encoderOutput: encoder, inputs: try decoder.prepareDecoderInputs(withPrompt: []),
                options: options),
            .init(encoderOutput: NotAnArray(), inputs: inputs, options: options),
        ]
        for window in windows {
            #expect(throws: (any Error).self) { try DecodeSession(decoder: decoder, window: window) }
        }
        decoder.tokenizer = nil
        #expect(throws: (any Error).self) {
            try DecodeSession(
                decoder: decoder, window: .init(encoderOutput: encoder, inputs: inputs, options: options))
        }
    }

    @Test(
        "throws when the model returns no output, no logits or no cache",
        arguments: ScriptedDecoder.Fault.allCases)
    func faults(_ fault: ScriptedDecoder.Fault) async throws {
        await #expect(throws: (any Error).self) {
            _ = try await Self.decode(ScriptedDecoder(script: [:], fault: fault))
        }
    }

    @Test("reports the options' temperature for a sampler that is not greedy")
    func temperatureOfOtherSamplers() {
        let options = Self.options { $0.temperature = 0.6 }

        #expect(
            DecodeSession.temperature(of: AllowedLanguageSampler(allowedTokens: []), options: options) == 0.6)
    }
}

/// A decoder whose dominant logit at each cache position comes from a script, defaulting to token 7.
final class ScriptedDecoder: TextDecoding {
    enum Fault: CaseIterable, Sendable { case noOutput, noLogits, noCache }

    var tokenizer: (any WhisperTokenizer)? = ScriptedTokenizer()
    var isModelMultilingual = true
    var logitsFilters: [any LogitsFiltering]?
    var supportsWordTimestamps: Bool { true }
    var logitsSize: Int? { DecoderPrefillTests.vocabularySize }
    var kvCacheEmbedDim: Int? { 2 }
    var kvCacheMaxSequenceLength: Int? { Constants.maxTokenContext }
    var windowSize: Int? { 3 }
    var embedSize: Int? { 3 }
    private let script: [Int: Int]
    private let delay: Duration
    private let fault: Fault?
    private(set) var fed: [Int] = []

    init(script: [Int: Int], delay: Duration = .zero, fault: Fault? = nil) {
        self.script = script
        self.delay = delay
        self.fault = fault
    }

    static func array(_ shape: [Int], dominant: Int? = nil) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float16)
        for index in 0..<array.count { array[index] = 0 }
        if let dominant { array[dominant] = 20 }
        return array
    }

    func predictLogits(_ inputs: any TextDecoderInputType) async throws -> (any TextDecoderOutputType)? {
        guard let inputs = inputs as? TextDecoderMLMultiArrayInputType, fault != .noOutput else { return nil }
        if delay > .zero { try await Task.sleep(for: delay) }
        fed.append(inputs.inputIds[0].intValue)
        let dominant = script[inputs.cacheLength[0].intValue] ?? 7
        let logits = try Self.array([1, 1, DecoderPrefillTests.vocabularySize], dominant: dominant)
        let cache = DecodingCache(
            keyCache: try Self.array([1, 2, 1, 1]), valueCache: try Self.array([1, 2, 1, 1]),
            alignmentWeights: try Self.array([1, 3]))
        return TextDecoderMLMultiArrayOutputType(
            logits: fault == .noLogits ? nil : logits, cache: fault == .noCache ? nil : cache)
    }

    func decodeText(
        from encoderOutput: any AudioEncoderOutputType, using decoderInputs: any DecodingInputsType,
        sampler tokenSampler: any TokenSampling, options decoderOptions: DecodingOptions,
        callback: TranscriptionCallback?
    ) async throws -> DecodingResult {
        throw WhisperError.decodingFailed("decoded only through the session")
    }

    func detectLanguage(
        from encoderOutput: any AudioEncoderOutputType, using decoderInputs: any DecodingInputsType,
        sampler tokenSampler: any TokenSampling, options: DecodingOptions, temperature: FloatType
    ) async throws -> DecodingResult {
        throw WhisperError.decodingFailed("not detected here")
    }
}

/// Spells each token as its id, and knows token 52 as the one language.
struct ScriptedTokenizer: WhisperTokenizer {
    func encode(text: String) -> [Int] { [] }
    func decode(tokens: [Int]) -> String { tokens.map(String.init).joined(separator: " ") }
    func convertTokenToId(_ token: String) -> Int? { nil }
    func convertIdToToken(_ id: Int) -> String? { nil }
    var specialTokens: SpecialTokens { DecoderPrefillTests.specialTokens }
    var allLanguageTokens: Set<Int> { [52] }
    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) { ([], []) }
}

/// An encoder output that is not the array the decoder reads.
private struct NotAnArray: AudioEncoderOutputType {}
