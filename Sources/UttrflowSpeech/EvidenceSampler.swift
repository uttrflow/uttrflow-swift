// The decoder's runner-up tokens at each step, read from logits the sampler already holds.
import CoreML
import Synchronization
import WhisperKit

/// The likeliest tokens at one decoder step, as log-probabilities over every finite logit.
enum TokenLeaders {
    /// How many leaders a step keeps, the count `Docs/decoder-evidence.md` measured the cost of.
    static let count = 5

    /// The logits as `Float`, read straight from the buffer in the type the model wrote them in.
    static func scores(of logits: MLMultiArray) -> [Float] {
        switch logits.dataType {
        case .float16:
            logits.withUnsafeBufferPointer(ofType: Float16.self) { $0.map(Float.init) }
        default:
            logits.withUnsafeBufferPointer(ofType: Float.self) { Array($0) }
        }
    }

    /// The log-sum-exp of the finite scores, or `nil` when none is finite.
    static func normaliser(of scores: [Float]) -> Float? {
        guard let top = scores.lazy.filter(\.isFinite).max() else { return nil }
        return top + log(scores.reduce(0) { $1.isFinite ? $0 + exp($1 - top) : $0 })
    }

    /// The `k` largest scores as log-probabilities, likeliest first.
    static func leaders(in scores: [Float], k: Int) -> [(token: Int, logProb: Float)] {
        guard let normaliser = normaliser(of: scores) else { return [] }
        var leaders: [(token: Int, logProb: Float)] = []
        for (token, score) in scores.enumerated() where score.isFinite {
            let logProb = score - normaliser
            guard leaders.count < k || logProb > leaders[leaders.count - 1].logProb else { continue }
            leaders.append((token, logProb))
            leaders.sort { $0.logProb > $1.logProb }
            if leaders.count > k { leaders.removeLast() }
        }
        return leaders
    }
}

/// Samples exactly as the wrapped sampler does and keeps each position's leaders. See `Docs/decoder-evidence.md`.
final class EvidenceSampler: TokenSampling {
    private let inner: any TokenSampling
    private let state = Mutex<(steps: [Int: [(token: Int, logProb: Float)]], lastTokens: [Int])>(([:], []))

    init(wrapping inner: any TokenSampling) {
        self.inner = inner
    }

    /// Keyed by `tokens.count`, the position being predicted; a prefill step is overwritten by the next call there.
    func update(tokens: [Int], logits: MLMultiArray, logProbs: [Float]) async -> SamplingResult {
        let leaders = TokenLeaders.leaders(in: TokenLeaders.scores(of: logits), k: TokenLeaders.count)
        state.withLock {
            $0.steps[tokens.count] = leaders
            $0.lastTokens = tokens
        }
        return await inner.update(tokens: tokens, logits: logits, logProbs: logProbs)
    }

    func finalize(tokens: [Int], logProbs: [Float]) -> SamplingResult {
        state.withLock { $0.lastTokens = tokens }
        return inner.finalize(tokens: tokens, logProbs: logProbs)
    }

    /// `tokenLogProbs` with each step's runner-ups added beside the chosen token, whose own value is kept.
    func tokenLogProbs(of result: DecodingResult) -> [[Int: Float]] {
        state.withLock { state in
            // WhisperKit cuts its result from the start-of-transcript token, the first token it returns.
            let start = result.tokens.first.flatMap { state.lastTokens.firstIndex(of: $0) } ?? 0
            return result.tokenLogProbs.enumerated().map { index, chosen in
                let rivals = state.steps[start + index] ?? []
                return rivals.reduce(into: chosen) { entry, rival in
                    if entry[rival.token] == nil { entry[rival.token] = rival.logProb }
                }
            }
        }
    }
}
