// One window's decode, stepped here on WhisperKit's public primitives rather than inside its loop.
import CoreML
import Foundation
import Synchronization
import UttrflowCore
import WhisperKit

/// Decodes one window token by token, as WhisperKit's own loop does. See `Docs/decode-session.md`.
struct DecodeSession {
    /// What the window is decoded from and how; one value so the session's initializer stays short.
    struct Window {
        let encoderOutput: any AudioEncoderOutputType
        let inputs: any DecodingInputsType
        let options: DecodingOptions
    }

    let decoder: any TextDecoding
    let tokenizer: any WhisperTokenizer
    let encoderOutput: MLMultiArray
    let inputs: DecodingInputs
    let options: DecodingOptions

    /// Refuses, with WhisperKit's own errors, the window its loop would refuse.
    init(decoder: any TextDecoding, window: Window) throws {
        guard let tokenizer = decoder.tokenizer else { throw WhisperError.tokenizerUnavailable() }
        guard let inputs = window.inputs as? DecodingInputs else {
            throw WhisperError.prepareDecoderInputsFailed("DecodingInputsType must be DecodingInputs")
        }
        guard !inputs.initialPrompt.isEmpty else {
            throw WhisperError.prepareDecoderInputsFailed("Initial prompt must not be empty")
        }
        guard let encoderOutput = window.encoderOutput as? MLMultiArray else {
            throw WhisperError.prepareDecoderInputsFailed("Input must be MLMultiArray")
        }
        self.decoder = decoder
        self.tokenizer = tokenizer
        self.inputs = inputs
        self.encoderOutput = encoderOutput
        self.options = window.options
    }

    /// The tokens and state carried from one step to the next.
    struct Progress {
        var tokens: [Int]
        var logProbs: [Float]
        var nextToken: Int
        var hasAlignment = false
        var isFirstTokenLogProbTooLow = false
        var timings = TranscriptionTimings()
        /// The prompt and timestamp split WhisperKit's timings have no field for.
        var split = RecognitionTimings.zero
    }

    /// Greedy or sampled decoding of the window, returning what WhisperKit's `decodeText` would.
    nonisolated(nonsending) func decode(
        sampler: any TokenSampling, callback: TranscriptionCallback?
    ) async throws -> DecodingResult {
        try await decodeSplit(sampler: sampler, callback: callback).result
    }

    /// The window's result, with the prompt steps, their model time and the timestamp steps it took.
    nonisolated(nonsending) func decodeSplit(
        sampler: any TokenSampling, callback: TranscriptionCallback?
    ) async throws -> (result: DecodingResult, split: RecognitionTimings) {
        let promptCount = inputs.initialPrompt.count
        var progress = Progress(
            tokens: inputs.initialPrompt, logProbs: Array(repeating: 0, count: promptCount),
            nextToken: inputs.initialPrompt[promptCount - 1])
        let filters = logitsFilters(promptCount: promptCount)
        let earlyStop = callback.map { EarlyStop(callback: $0) }
        // `sampleLength` counts sampled tokens only, not the prefill steps before them.
        let loopCount = min(promptCount - 1 + options.sampleLength, Constants.maxTokenContext - 1)
        for index in 0..<loopCount {
            let finished = try await step(
                index, progress: &progress, filters: filters, sampler: sampler, earlyStop: earlyStop)
            if finished || earlyStop?.isRequested == true { break }
        }
        return (result(of: progress, sampler: sampler), progress.split)
    }

    /// One model step at `index`; true when the segment is complete and nothing was appended.
    nonisolated(nonsending) private func step(
        _ index: Int, progress: inout Progress, filters: [any LogitsFiltering],
        sampler: any TokenSampling, earlyStop: EarlyStop?
    ) async throws -> Bool {
        let loopStart = Date()
        let promptCount = inputs.initialPrompt.count
        let isPrefill = index < promptCount - 1
        force(index, progress: &progress, isLastPrefill: index == promptCount - 1)
        inputs.inputIds[0] = NSNumber(value: progress.nextToken)
        inputs.cacheLength[0] = NSNumber(value: index)
        let inferenceStart = Date()
        let output = try await predict()
        let inference = Date().timeIntervalSince(inferenceStart)
        progress.timings.decodingPredictions += inference
        let nonInferenceStart = Date()
        let logits = filters.reduce(try Self.logits(of: output)) {
            $1.filterLogits($0, withTokens: progress.tokens)
        }
        progress.timings.decodingFiltering += Date().timeIntervalSince(nonInferenceStart)
        let samplingStart = Date()
        let sampled = await sampler.update(
            tokens: progress.tokens, logits: logits, logProbs: progress.logProbs)
        progress.timings.decodingSampling += Date().timeIntervalSince(samplingStart)
        guard let next = sampled.tokens.last, let nextLogProb = sampled.logProbs.last else {
            throw WhisperError.decodingLogitsFailed("Sampler returned no token")
        }
        progress.nextToken = next
        progress.isFirstTokenLogProbTooLow =
            index == max(0, promptCount - 1)
            && options.firstTokenLogProbThreshold.map { nextLogProb < $0 } == true
        // An end of text sampled while the prompt is still forced is discarded, as WhisperKit discards it.
        let completed =
            (sampled.completed && !isPrefill) || progress.tokens.count >= Constants.maxTokenContext - 1
            || progress.isFirstTokenLogProbTooLow
        if !completed {
            try advance(
                index, output: output, isPrefill: isPrefill, logProb: nextLogProb, progress: &progress)
            earlyStop?.report(transcriptionProgress(of: progress), isPrefill: isPrefill)
        }
        let isTimestamp = !isPrefill && !completed && next >= tokenizer.specialTokens.timeTokenBegin
        progress.split = progress.split.adding(
            RecognitionTimings(
                promptSteps: isPrefill ? 1 : 0, promptStepSeconds: isPrefill ? inference : 0,
                timestampSteps: isTimestamp ? 1 : 0))
        progress.timings.decodingNonPrediction += Date().timeIntervalSince(nonInferenceStart)
        progress.timings.decodingLoop += Date().timeIntervalSince(loopStart)
        progress.timings.totalDecodingLoops += 1
        if index == 0, !completed { progress.timings.firstTokenTime = CFAbsoluteTimeGetCurrent() }
        return completed
    }

    /// Feeds the prompt token at `index`, unless the model already chose a timestamp where the prompt ends on one.
    private func force(_ index: Int, progress: inout Progress, isLastPrefill: Bool) {
        guard index < inputs.initialPrompt.count else { return }
        let timeTokenBegin = tokenizer.specialTokens.timeTokenBegin
        let bothTimestamps = progress.tokens[index] >= timeTokenBegin && progress.nextToken >= timeTokenBegin
        if isLastPrefill && bothTimestamps {
            progress.tokens[index] = progress.nextToken
        } else {
            progress.nextToken = progress.tokens[index]
        }
    }

    /// The decoder's output for the inputs as they stand.
    nonisolated(nonsending) private func predict() async throws -> TextDecoderMLMultiArrayOutputType {
        let output =
            try await decoder.predictLogits(
                TextDecoderMLMultiArrayInputType(
                    inputIds: inputs.inputIds, cacheLength: inputs.cacheLength, keyCache: inputs.keyCache,
                    valueCache: inputs.valueCache, kvCacheUpdateMask: inputs.kvCacheUpdateMask,
                    encoderOutputEmbeds: encoderOutput, decoderKeyPaddingMask: inputs.decoderKeyPaddingMask))
            as? TextDecoderMLMultiArrayOutputType
        guard let output else { throw WhisperError.decodingLogitsFailed("Unable to decode logits") }
        return output
    }

    private static func logits(of output: TextDecoderMLMultiArrayOutputType) throws -> MLMultiArray {
        guard let logits = output.logits else { throw WhisperError.decodingLogitsFailed("Missing logits") }
        return logits
    }

    /// Keeps the sampled token past the prefill and writes this step's keys, values and alignment into the cache.
    private func advance(
        _ index: Int, output: TextDecoderMLMultiArrayOutputType, isPrefill: Bool, logProb: Float,
        progress: inout Progress
    ) throws {
        if !isPrefill {
            progress.tokens.append(progress.nextToken)
            progress.logProbs.append(logProb)
        }
        guard let keys = output.cache?.keyCache, let values = output.cache?.valueCache else {
            throw WhisperError.decodingLogitsFailed("Invalid model output")
        }
        let kvStart = Date()
        TextDecoder.updateKVCache(
            keyTensor: inputs.keyCache, keySlice: keys, valueTensor: inputs.valueCache, valueSlice: values,
            insertAtIndex: index)
        inputs.decoderKeyPaddingMask[index + 1] = 0
        inputs.kvCacheUpdateMask[index] = 0
        inputs.kvCacheUpdateMask[index + 1] = 1
        if let alignment = output.cache?.alignmentWeights {
            progress.hasAlignment = true
            TextDecoder.updateAlignmentWeights(
                alignmentTensor: inputs.alignmentWeights, alignmentSlice: alignment, insertAtIndex: index)
        }
        progress.timings.decodingKvCaching += Date().timeIntervalSince(kvStart)
        progress.timings.totalKVUpdateRuns += 1
    }
}
