// A fallback window's sampling, drawn from a fixed seed so the same audio gives the same words.
import CoreML
import Synchronization
import UttrflowCore
import WhisperKit

/// Samples a warmer window as WhisperKit's greedy sampler does, from a fixed seed. See `Docs/decode-session.md`.
final class SeededFallbackSampler: TokenSampling {
    /// Any fixed value repeats a run; this one means nothing else.
    static let seed: UInt64 = 0

    private let temperature: Float
    private let topK: Int
    private let endToken: Int
    private let generator = Mutex(SeededGenerator(seed: seed))

    /// The seeded sampler at a warmer `temperature`, or `sampler` itself at temperature 0, which draws nothing.
    static func replacing(
        _ sampler: any TokenSampling, temperature: Float, options: DecodingOptions, endToken: Int
    ) -> any TokenSampling {
        guard temperature > 0 else { return sampler }
        return SeededFallbackSampler(temperature: temperature, topK: options.topK, endToken: endToken)
    }

    private init(temperature: Float, topK: Int, endToken: Int) {
        self.temperature = temperature
        self.topK = topK
        self.endToken = endToken
    }

    /// One draw from the `topK` likeliest tokens at this temperature, weighted by their probabilities.
    func update(tokens: [Int], logits: MLMultiArray, logProbs: [Float]) async -> SamplingResult {
        let scaled = TokenLeaders.scores(of: logits).map { $0 / temperature }
        let leaders = TokenLeaders.leaders(in: scaled, k: topK)
        let total = leaders.reduce(Float(0)) { $0 + exp($1.logProb) }
        let draw = generator.withLock { Float.random(in: 0..<1, using: &$0) } * total
        var reached = Float(0)
        // No finite score leaves nothing to draw from, so the window ends as a model with no answer would.
        let chosen =
            leaders.first { leader in
                reached += exp(leader.logProb)
                return draw < reached
            } ?? leaders.last ?? (token: endToken, logProb: -.infinity)
        return SamplingResult(
            tokens: tokens + [chosen.token], logProbs: logProbs + [chosen.logProb],
            completed: chosen.token == endToken)
    }

    /// Ends the window on the end token, as WhisperKit's greedy sampler does.
    func finalize(tokens: [Int], logProbs: [Float]) -> SamplingResult {
        guard tokens.last != endToken else {
            return SamplingResult(tokens: tokens, logProbs: logProbs, completed: true)
        }
        return SamplingResult(tokens: tokens + [endToken], logProbs: logProbs + [0], completed: true)
    }
}
