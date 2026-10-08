// Records the decoder's per-step log-probabilities for the relisten probe.
import CoreML
private import Foundation
import UttrflowEval
import WhisperKit

/// A decoder that hands each step's log-probabilities of the prompt tokens to the probe.
final class RecordingDecoder: TextDecoding {
    private var inner: any TextDecoding
    /// Per model call, the log-probability of every token that appears in the window's prompt.
    private(set) var steps: [[Int: Float]] = []
    /// Per model call, the step's leader and runner-up.
    private(set) var leaders: [CandidateSeparation.GreedyStep?] = []
    private(set) var promptCount = 0
    /// The audio of the decode under way, kept so a forced decode reuses the clip it scores.
    var samples: [Float] = []

    init(wrapping inner: any TextDecoding) { self.inner = inner }

    /// Clears the record; only the next window decoded is recorded, so a second window cannot shift the steps.
    func start() {
        steps = []
        leaders = []
        promptCount = 0
        isRecording = true
    }

    private var isRecording = false

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
        from encoderOutput: any AudioEncoderOutputType, using decoderInputs: any DecodingInputsType,
        sampler tokenSampler: any TokenSampling, options decoderOptions: DecodingOptions,
        callback: TranscriptionCallback?
    ) async throws -> DecodingResult {
        guard isRecording else {
            return try await inner.decodeText(
                from: encoderOutput, using: decoderInputs, sampler: tokenSampler, options: decoderOptions,
                callback: callback)
        }
        isRecording = false
        let prompt = (decoderInputs as? DecodingInputs)?.initialPrompt ?? []
        promptCount = prompt.count
        let recording = WatchedTokenSampler(wrapping: tokenSampler, watched: Set(prompt)) { [weak self] in
            self?.steps.append($0)
            self?.leaders.append($1)
        }
        return try await inner.decodeText(
            from: encoderOutput, using: decoderInputs, sampler: recording, options: decoderOptions,
            callback: callback)
    }

    func detectLanguage(
        from encoderOutput: any AudioEncoderOutputType, using decoderInputs: any DecodingInputsType,
        sampler tokenSampler: any TokenSampling, options: DecodingOptions, temperature: FloatType
    ) async throws -> DecodingResult {
        try await inner.detectLanguage(
            from: encoderOutput, using: decoderInputs, sampler: tokenSampler, options: options,
            temperature: temperature)
    }
}

/// Passes each step through, first noting the log-probability of every watched token.
struct WatchedTokenSampler: TokenSampling {
    let inner: any TokenSampling
    let watched: Set<Int>
    let record: ([Int: Float], CandidateSeparation.GreedyStep?) -> Void

    init(
        wrapping inner: any TokenSampling, watched: Set<Int>,
        record: @escaping ([Int: Float], CandidateSeparation.GreedyStep?) -> Void
    ) {
        self.inner = inner
        self.watched = watched
        self.record = record
    }

    func update(tokens: [Int], logits: MLMultiArray, logProbs: [Float]) async -> SamplingResult {
        let count = logits.count
        var scores = [Float](repeating: 0, count: count)
        for index in 0..<count { scores[index] = logits[index].floatValue }
        let top = scores.max() ?? 0
        let normaliser = top + log(scores.reduce(0) { $0 + exp($1 - top) })
        record(
            Dictionary(
                uniqueKeysWithValues: watched.filter { $0 < count }.map { ($0, scores[$0] - normaliser) }),
            CandidateSeparation.GreedyStep(logProbabilities: scores.map { $0 - normaliser }))
        return await inner.update(tokens: tokens, logits: logits, logProbs: logProbs)
    }

    func finalize(tokens: [Int], logProbs: [Float]) -> SamplingResult {
        inner.finalize(tokens: tokens, logProbs: logProbs)
    }
}
