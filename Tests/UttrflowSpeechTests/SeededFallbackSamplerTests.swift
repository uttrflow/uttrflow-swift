// Pins that a fallback window draws its tokens the same way on every run, from the likeliest few.
import CoreML
import Testing
import WhisperKit

@testable import UttrflowSpeech

@Suite("Sampling a fallback window from a fixed seed")
struct SeededFallbackSamplerTests {
    static let endToken = 9

    static func sampler(temperature: Float, topK: Int = 5) -> any TokenSampling {
        var options = DecodingOptions()
        options.topK = topK
        return SeededFallbackSampler.replacing(
            EvidenceSamplerTests.Scripted(token: 0), temperature: temperature, options: options,
            endToken: endToken)
    }

    /// The tokens a fresh sampler draws over `steps` steps of the same logits.
    static func draws(_ scores: [Int: Float], steps: Int, topK: Int = 5) async throws -> [Int] {
        let sampler = sampler(temperature: 1, topK: topK)
        let logits = try EvidenceSamplerTests.logits(scores)
        var tokens: [Int] = []
        for _ in 0..<steps {
            tokens = await sampler.update(tokens: tokens, logits: logits, logProbs: []).tokens
        }
        return tokens
    }

    @Test("leaves a greedy window to the sampler it was handed")
    func greedyIsUntouched() {
        #expect(Self.sampler(temperature: 0) is EvidenceSamplerTests.Scripted)
        #expect(Self.sampler(temperature: 0.2) is SeededFallbackSampler)
    }

    @Test("a fresh sampler draws the same tokens from the same logits")
    func drawsRepeat() async throws {
        let scores: [Int: Float] = [0: 1, 1: 1, 2: 1, 3: 1, 4: 1]

        let first = try await Self.draws(scores, steps: 40)

        #expect(Set(first).count > 1)
        #expect(first == (try await Self.draws(scores, steps: 40)))
    }

    @Test("draws only from the likeliest top-k tokens")
    func drawsFromTheLeaders() async throws {
        let tokens = try await Self.draws([0: 3, 1: 3, 2: 0, 3: 0], steps: 40, topK: 2)

        #expect(Set(tokens) == [0, 1])
    }

    @Test("carries the drawn token's log-probability at that temperature, and ends on the end token")
    func logProbabilityAndEnd() async throws {
        let sampler = Self.sampler(temperature: 0.5)

        let result = await sampler.update(
            tokens: [1], logits: try EvidenceSamplerTests.logits([Self.endToken: 1]), logProbs: [0])

        #expect(result.tokens == [1, Self.endToken])
        #expect(result.logProbs == [0, 0])
        #expect(result.completed)
    }

    @Test("ends the window when no token has a finite score")
    func nothingToDraw() async throws {
        let result = await Self.sampler(temperature: 1).update(
            tokens: [1], logits: try EvidenceSamplerTests.logits([:]), logProbs: [0])

        #expect(result.tokens == [1, Self.endToken])
        #expect(result.completed)
    }

    @Test("never draws a token past the vocabulary from the padding stored after it")
    func drawsOnlyFromTheVocabulary() async throws {
        let sampler = Self.sampler(temperature: 1)
        let logits = try EvidenceSamplerTests.padded([0, 0, 0], padding: 6, filler: 50)

        for _ in 0..<20 {
            let drawn = await sampler.update(tokens: [], logits: logits, logProbs: []).tokens
            #expect(drawn.allSatisfy { $0 < 3 })
        }
    }

    @Test("closes a window on the end token exactly once")
    func finalizeAppendsTheEndOnce() {
        let sampler = Self.sampler(temperature: 1)

        #expect(sampler.finalize(tokens: [1, 2], logProbs: [0, -1]).tokens == [1, 2, Self.endToken])
        let ended = sampler.finalize(tokens: [1, Self.endToken], logProbs: [0, -1])

        #expect(ended.tokens == [1, Self.endToken])
    }
}
