// The parity gate for owning the decode loop: the session against WhisperKit's loop, window by window.
import CoreML
import Foundation
import Synchronization
import Testing
import UttrflowCore
import WhisperKit

@testable import UttrflowSpeech

/// One window decoded both ways from identical inputs, and what each cost.
struct ParityWindow: Sendable {
    let identical: Bool
    let steps: Int
    let library: Duration
    let session: Duration
}

/// The shipping decoder, which also decodes every greedy window through both loops and compares them.
final class ParityDecoder: TextDecoding {
    private var held: LanguageHeldDecoder
    private let library: any TextDecoding
    private let windows = Mutex<[ParityWindow]>([])
    private let order = Mutex(false)

    init(library: any TextDecoding) {
        self.library = library
        held = LanguageHeldDecoder(wrapping: library, languages: LanguageCode.transcribed)
    }

    var compared: [ParityWindow] { windows.withLock { $0 } }

    var tokenizer: (any WhisperTokenizer)? {
        get { held.tokenizer }
        set { held.tokenizer = newValue }
    }
    var isModelMultilingual: Bool {
        get { held.isModelMultilingual }
        set { held.isModelMultilingual = newValue }
    }
    var logitsFilters: [any LogitsFiltering]? {
        get { held.logitsFilters }
        set { held.logitsFilters = newValue }
    }
    var supportsWordTimestamps: Bool { held.supportsWordTimestamps }
    var logitsSize: Int? { held.logitsSize }
    var kvCacheEmbedDim: Int? { held.kvCacheEmbedDim }
    var kvCacheMaxSequenceLength: Int? { held.kvCacheMaxSequenceLength }
    var windowSize: Int? { held.windowSize }
    var embedSize: Int? { held.embedSize }

    func predictLogits(_ inputs: any TextDecoderInputType) async throws -> (any TextDecoderOutputType)? {
        try await held.predictLogits(inputs)
    }
    func prepareDecoderInputs(withPrompt initialPrompt: [Int]) throws -> any DecodingInputsType {
        try held.prepareDecoderInputs(withPrompt: initialPrompt)
    }
    func prefillDecoderInputs(
        _ decoderInputs: any DecodingInputsType, withOptions options: DecodingOptions?
    ) async throws -> any DecodingInputsType {
        try await held.prefillDecoderInputs(decoderInputs, withOptions: options)
    }
    func detectLanguage(
        from encoderOutput: any AudioEncoderOutputType, using decoderInputs: any DecodingInputsType,
        sampler tokenSampler: any TokenSampling, options: DecodingOptions, temperature: FloatType
    ) async throws -> DecodingResult {
        try await held.detectLanguage(
            from: encoderOutput, using: decoderInputs, sampler: tokenSampler, options: options,
            temperature: temperature)
    }

    func decodeText(
        from encoderOutput: any AudioEncoderOutputType, using decoderInputs: any DecodingInputsType,
        sampler tokenSampler: any TokenSampling, options decoderOptions: DecodingOptions,
        callback: TranscriptionCallback?
    ) async throws -> DecodingResult {
        if let greedy = tokenSampler as? GreedyTokenSampler, greedy.temperature == 0,
            let inputs = decoderInputs as? DecodingInputs
        {
            try await compare(encoderOutput: encoderOutput, inputs: inputs, options: decoderOptions)
        }
        return try await held.decodeText(
            from: encoderOutput, using: decoderInputs, sampler: tokenSampler, options: decoderOptions,
            callback: callback)
    }

    /// Decodes copies of `inputs` through both loops, alternating which runs first.
    nonisolated(nonsending) private func compare(
        encoderOutput: any AudioEncoderOutputType, inputs: DecodingInputs, options: DecodingOptions
    ) async throws {
        let clock = ContinuousClock()
        let eot = held.tokenizer?.specialTokens.endToken ?? 0
        let sampler = { GreedyTokenSampler(temperature: 0, eotToken: eot, decodingOptions: options) }
        let libraryFirst = order.withLock {
            $0.toggle(); return $0
        }
        var libraryResult: DecodingResult?
        var sessionResult: DecodingResult?
        var libraryTime = Duration.zero
        var sessionTime = Duration.zero
        for pass in libraryFirst ? [true, false] : [false, true] {
            let copy = Self.copy(inputs)
            let started = clock.now
            if pass {
                libraryResult = try await library.decodeText(
                    from: encoderOutput, using: copy, sampler: sampler(), options: options, callback: nil)
                libraryTime = started.duration(to: clock.now)
            } else {
                let session = try DecodeSession(
                    decoder: library,
                    window: .init(encoderOutput: encoderOutput, inputs: copy, options: options))
                sessionResult = try await session.decode(sampler: sampler(), callback: nil)
                sessionTime = started.duration(to: clock.now)
            }
        }
        guard let libraryResult, let sessionResult else { return }
        let window = ParityWindow(
            identical: Self.identical(libraryResult, sessionResult),
            steps: Int(libraryResult.timings?.totalDecodingLoops ?? 0),
            library: libraryTime, session: sessionTime)
        windows.withLock { $0.append(window) }
    }

    static func identical(_ lhs: DecodingResult, _ rhs: DecodingResult) -> Bool {
        lhs.tokens == rhs.tokens && lhs.tokenLogProbs == rhs.tokenLogProbs && lhs.text == rhs.text
            && lhs.avgLogProb.bitPattern == rhs.avgLogProb.bitPattern
            && lhs.compressionRatio.bitPattern == rhs.compressionRatio.bitPattern
            && lhs.language == rhs.language && lhs.temperature == rhs.temperature
            && lhs.fallback?.fallbackReason == rhs.fallback?.fallbackReason
            && lhs.timings?.totalDecodingLoops == rhs.timings?.totalDecodingLoops
            && bytes(lhs.cache?.alignmentWeights) == bytes(rhs.cache?.alignmentWeights)
            && bytes(lhs.cache?.keyCache) == bytes(rhs.cache?.keyCache)
    }

    static func bytes(_ array: MLMultiArray?) -> Data? {
        array.map { array in array.withUnsafeBytes { Data($0) } }
    }

    static func copy(_ inputs: DecodingInputs) -> DecodingInputs {
        func clone(_ array: MLMultiArray) -> MLMultiArray {
            MLMultiArray(concatenating: [array], axis: 0, dataType: array.dataType)
        }
        return DecodingInputs(
            initialPrompt: inputs.initialPrompt, inputIds: clone(inputs.inputIds),
            cacheLength: clone(inputs.cacheLength), keyCache: clone(inputs.keyCache),
            valueCache: clone(inputs.valueCache), alignmentWeights: clone(inputs.alignmentWeights),
            kvCacheUpdateMask: clone(inputs.kvCacheUpdateMask),
            decoderKeyPaddingMask: clone(inputs.decoderKeyPaddingMask))
    }
}

/// The real model on real audio, run only when `UTTRFLOW_PROBE_AUDIO` names files and the model is installed.
@Suite(
    "The decode session matches WhisperKit's loop on the shipping model",
    .enabled(if: ProbeInputs.isRunnable, "set UTTRFLOW_PROBE_AUDIO and install the shipping model"))
struct DecodeSessionParityProbe {
    @Test("every greedy window decodes to identical tokens, log-probabilities and alignment, three runs over")
    func parity() async throws {
        let kit = try await WhisperKit(
            WhisperKitConfig(
                modelFolder: ProbeInputs.modelFolder.path, tokenizerFolder: ProbeInputs.modelFolder,
                verbose: false, logLevel: .error, prewarm: true, load: true, download: false))
        let decoder = ParityDecoder(library: kit.textDecoder)
        kit.textDecoder = decoder
        var transcripts: [String: Set<String>] = [:]
        for _ in 0..<3 {
            for path in ProbeInputs.audioPaths {
                let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
                var options = VocabularyPrompt.decodingOptions(languageHint: nil)
                options.wordTimestamps = true
                let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
                let words = results.flatMap(\.allWords).map { "\($0.word)@\($0.start)-\($0.end)" }
                transcripts[path, default: []].insert(words.joined(separator: " "))
            }
        }
        Self.report(decoder.compared, transcripts: transcripts)
        #expect(decoder.compared.allSatisfy { $0.identical })
        #expect(transcripts.values.allSatisfy { $0.count == 1 })
    }

    static func report(_ windows: [ParityWindow], transcripts: [String: Set<String>]) {
        let steps = max(windows.map(\.steps).reduce(0, +), 1)
        let library = windows.map(\.library).reduce(.zero, +) / steps
        let session = windows.map(\.session).reduce(.zero, +) / steps
        print("PARITY windows=\(windows.count) identical=\(windows.filter(\.identical).count) steps=\(steps)")
        print("PARITY per-step library=\(library) session=\(session)")
        for (path, runs) in transcripts.sorted(by: { $0.key < $1.key }) {
            print("PARITY \(URL(fileURLWithPath: path).lastPathComponent) distinct-runs=\(runs.count)")
        }
    }
}
