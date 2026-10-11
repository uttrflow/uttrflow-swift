import Foundation
import MLX
import MLXLMCommon
import Testing

@testable import UttrflowLocalModel

/// A vocabulary small enough to name every token: 0 " x", 1 " y", 2 " z", 3 newline.
private let vocabulary = TokenHealing.Vocabulary(texts: [" x", " y", " z", "\n"], ending: [3])

/// The model's own logits for one step: it finds " x" far less likely than the other three tokens.
private let modelLogits: [Float] = [-4, 6, 6, 6]

/// The log-probability of " x" over the whole vocabulary, worked out by hand.
private let unmaskedLogProbability = Double(-4) - log(exp(-4) + 3 * exp(6))

/// Whether this test build carries MLX's Metal shaders: an `xcodebuild test` build does, a `swift test` build does not.
private let carriesMetalShaders =
    Bundle(for: ShaderProbe.self).url(forResource: "mlx-swift_Cmlx", withExtension: "bundle") != nil

private final class ShaderProbe {}

@Suite(
    "Scoring a sampled token over the model's own distribution",
    .enabled(if: carriesMetalShaders, "MLX evaluates only where its Metal shaders are bundled"))
struct RecordingSamplerTests {
    /// Runs one decode step as `TokenIterator` does: the processor masks, then the sampler picks and records.
    private func step(
        masking: any LogitProcessor, scoredOverModel: Bool
    ) -> (tokens: [Int], logProbabilities: [Double]) {
        let ledger = SampleLedger()
        let unmasked = UnmaskedLogits(masking: masking)
        let sampler = RecordingSampler(
            inner: ArgMaxSampler(), ledger: ledger, unmasked: scoredOverModel ? unmasked : nil)
        let masked = unmasked.process(logits: MLXArray(modelLogits, [1, modelLogits.count]))
        unmasked.didSample(token: sampler.sample(logits: masked))
        return ledger.read()
    }

    @Test("A token the only allowed choice forced is scored as the model found it, not as certain")
    func aForcedTokenKeepsTheModelsDoubt() throws {
        let recorded = step(
            masking: TokenChoice(vocabulary: vocabulary, choices: [" x"]), scoredOverModel: true)
        #expect(recorded.tokens == [0])
        let score = try #require(recorded.logProbabilities.first)
        #expect(abs(score - unmaskedLogProbability) < 0.01)
        #expect(score < -1)
    }

    @Test("A step no processor masks is scored the same with or without the unmasked logits")
    func anUnmaskedStepIsUnchanged() throws {
        let free = TokenChoice(vocabulary: vocabulary, choices: [])
        let paired = try #require(step(masking: free, scoredOverModel: true).logProbabilities.first)
        let plain = try #require(step(masking: free, scoredOverModel: false).logProbabilities.first)
        #expect(abs(paired - plain) < 0.0001)
    }
}
