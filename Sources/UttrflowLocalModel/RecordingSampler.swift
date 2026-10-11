import Foundation
import MLX
import MLXLMCommon

/// Every token a pass sampled and how likely the model found it, written by the sampler and read once the decode has stopped.
final class SampleLedger: @unchecked Sendable {
    // The decode writes while the pass reads only after it ended; the lock covers the step a cancel leaves running.
    private let lock = NSLock()
    private var tokens: [MLXArray] = []
    private var logProbabilities: [MLXArray] = []

    /// Records one step's token and its log-probability, both still lazy.
    func record(token: MLXArray, logProbability: MLXArray) {
        lock.withLock {
            tokens.append(token)
            logProbabilities.append(logProbability)
        }
    }

    /// The sampled token ids and their log-probabilities in order, evaluated now.
    func read() -> (tokens: [Int], logProbabilities: [Double]) {
        let (sampled, scored) = lock.withLock { (tokens, logProbabilities) }
        guard !sampled.isEmpty, sampled.count == scored.count else { return ([], []) }
        let ids = concatenated(sampled.map { $0.reshaped([-1])[0..<1].asType(.int32) })
        let values = concatenated(scored.map { $0.reshaped([-1])[0..<1] })
        eval(ids, values)
        return (ids.asArray(Int32.self).map(Int.init), values.asArray(Float.self).map(Double.init))
    }
}

/// Passes a masking processor's work through and keeps the logits from before its mask, which the paired sampler scores.
final class UnmaskedLogits: LogitProcessor {
    private var masking: any LogitProcessor
    /// The last step's logits as the model put them out, before any token was forbidden.
    private(set) var latest: MLXArray?

    init(masking: any LogitProcessor) {
        self.masking = masking
    }

    func prompt(_ prompt: MLXArray) {
        masking.prompt(prompt)
    }

    func process(logits: MLXArray) -> MLXArray {
        latest = logits
        return masking.process(logits: logits)
    }

    func didSample(token: MLXArray) {
        masking.didSample(token: token)
    }
}

/// Samples as `inner` does and records how likely the chosen token was, so a line is scored from the pass that wrote it.
struct RecordingSampler: LogitSampler {
    let inner: any LogitSampler
    let ledger: SampleLedger
    /// Set when a processor masks the step: a token it forced is scored over the model's own logits, not the few it allowed.
    var unmasked: UnmaskedLogits?

    func sample(logits: MLXArray) -> MLXArray {
        let token = inner.sample(logits: logits)
        // Float32, since the bf16 logits would round every log-probability to a coarse grid.
        let scores = (unmasked?.latest ?? logits).asType(.float32)
        let chosen = takeAlong(scores, token.asType(.int32).reshaped([-1, 1]), axis: -1).reshaped([-1])
        let logProbability = chosen - logSumExp(scores, axis: -1).reshaped([-1])
        asyncEval(logProbability)
        ledger.record(token: token, logProbability: logProbability)
        return token
    }
}
