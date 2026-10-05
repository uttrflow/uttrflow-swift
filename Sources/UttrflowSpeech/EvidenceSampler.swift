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

    /// The entropy in nats of the softmax over the finite scores, or `nil` when none is finite.
    static func entropy(of scores: [Float]) -> Float? {
        guard let normaliser = normaliser(of: scores) else { return nil }
        return scores.reduce(0) { total, score in
            guard score.isFinite else { return total }
            let logProb = score - normaliser
            return total - exp(logProb) * logProb
        }
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

/// One decode window's per-step entropy, which WhisperKit's result types have no slot for.
public struct DecodeWindowEvidence: Equatable, Sendable {
    /// The tokens the window returned, from the start-of-transcript token.
    public let tokens: [Int]
    /// The entropy in nats before each token in `tokens`; `nil` where no step was recorded.
    public let entropies: [Float?]
    /// The temperature the window was sampled at.
    public let temperature: Float
}

/// The decode windows recorded since the last drain, the oldest dropped past `capacity`.
public final class DecodeWindowLog: Sendable {
    /// How many windows are kept when nothing drains them, so an unread log stays bounded.
    public static let capacity = 64
    private let windows = Mutex<[DecodeWindowEvidence]>([])

    public init() {}

    func append(_ window: DecodeWindowEvidence) {
        windows.withLock {
            $0.append(window)
            if $0.count > Self.capacity { $0.removeFirst($0.count - Self.capacity) }
        }
    }

    /// The recorded windows in decode order, leaving the log empty.
    public func drain() -> [DecodeWindowEvidence] {
        windows.withLock { windows in
            defer { windows.removeAll() }
            return windows
        }
    }
}

/// One position's leaders and entropy.
private struct Step {
    let leaders: [(token: Int, logProb: Float)]
    let entropy: Float?
}

/// Samples as the wrapped sampler does, keeping each step's leaders and entropy. See `Docs/decoder-evidence.md`.
final class EvidenceSampler: TokenSampling {
    private let inner: any TokenSampling
    private let state = Mutex<(steps: [Int: Step], lastTokens: [Int])>(([:], []))

    init(wrapping inner: any TokenSampling) {
        self.inner = inner
    }

    /// Keyed by `tokens.count`, the position being predicted; a prefill step is overwritten by the next call there.
    func update(tokens: [Int], logits: MLMultiArray, logProbs: [Float]) async -> SamplingResult {
        let scores = TokenLeaders.scores(of: logits)
        let step = Step(
            leaders: TokenLeaders.leaders(in: scores, k: TokenLeaders.count),
            entropy: TokenLeaders.entropy(of: scores))
        state.withLock {
            $0.steps[tokens.count] = step
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
            let start = Self.start(of: result, in: state.lastTokens)
            return result.tokenLogProbs.enumerated().map { index, chosen in
                let rivals = state.steps[start + index]?.leaders ?? []
                return rivals.reduce(into: chosen) { entry, rival in
                    if entry[rival.token] == nil { entry[rival.token] = rival.logProb }
                }
            }
        }
    }

    /// The window's entropy before each returned token, aligned as `tokenLogProbs(of:)` aligns leaders.
    func window(of result: DecodingResult) -> DecodeWindowEvidence {
        let entropies = state.withLock { state in
            let start = Self.start(of: result, in: state.lastTokens)
            return result.tokens.indices.map { state.steps[start + $0]?.entropy }
        }
        return DecodeWindowEvidence(
            tokens: result.tokens, entropies: entropies, temperature: result.temperature)
    }

    /// WhisperKit cuts its result from the start-of-transcript token, the first token it returns.
    private static func start(of result: DecodingResult, in lastTokens: [Int]) -> Int {
        result.tokens.first.flatMap { lastTokens.firstIndex(of: $0) } ?? 0
    }
}
