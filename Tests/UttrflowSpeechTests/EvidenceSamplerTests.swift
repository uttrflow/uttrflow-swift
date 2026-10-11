// Pins the shape of the runner-up tokens the decoder carries beside each chosen token.
import CoreML
import Testing
import WhisperKit

@testable import UttrflowSpeech

@Suite("Recording each decoder step's leaders")
struct EvidenceSamplerTests {
    static let startOfTranscript = 50
    static let endOfText = 9

    /// Single-precision logits over ten tokens, minus infinity wherever `scores` names nothing.
    static func logits(_ scores: [Int: Float]) throws -> MLMultiArray {
        let logits = try MLMultiArray(shape: [1, 1, 10], dataType: .float32)
        for index in 0..<10 { logits[index] = NSNumber(value: scores[index] ?? -Float.infinity) }
        return logits
    }

    /// `scores` as the decoder writes them: one row whose storage runs `padding` slots past the vocabulary.
    static func padded(_ scores: [Float], padding: Int, filler: Float) throws -> MLMultiArray {
        let stored = scores.count + padding
        let storage = UnsafeMutablePointer<Float>.allocate(capacity: stored)
        storage.initialize(repeating: filler, count: stored)
        for (index, score) in scores.enumerated() { storage[index] = score }
        return try MLMultiArray(
            dataPointer: storage, shape: [1, 1, NSNumber(value: scores.count)], dataType: .float32,
            strides: [NSNumber(value: stored), NSNumber(value: stored), 1]
        ) { $0.deallocate() }
    }

    /// Picks whatever token it was told to, as the greedy sampler picks the argmax.
    struct Scripted: TokenSampling {
        let token: Int
        func update(tokens: [Int], logits: MLMultiArray, logProbs: [Float]) async -> SamplingResult {
            SamplingResult(tokens: tokens + [token], logProbs: logProbs + [-0.1], completed: false)
        }
        func finalize(tokens: [Int], logProbs: [Float]) -> SamplingResult {
            SamplingResult(
                tokens: tokens + [EvidenceSamplerTests.endOfText], logProbs: logProbs + [0], completed: true)
        }
    }

    @Test("the leaders are the k largest finite scores as log-probabilities, likeliest first")
    func leadersAreTheLargest() {
        let scores: [Float] = [0, 2, -.infinity, 1, 3]
        let normaliser = log(exp(Float(0)) + exp(2) + exp(1) + exp(3))

        let leaders = TokenLeaders.leaders(in: scores, k: 2)

        #expect(leaders.map(\.token) == [4, 1])
        #expect(abs(leaders[1].logProb - (2 - normaliser)) < 1e-5)
        #expect(TokenLeaders.leaders(in: [-.infinity], k: 2).isEmpty)
    }

    @Test("samples exactly as the sampler it wraps")
    func samplingIsUnchanged() async throws {
        let sampler = EvidenceSampler(wrapping: Scripted(token: 7))

        let result = await sampler.update(tokens: [1], logits: try Self.logits([3: 5, 7: 1]), logProbs: [0])

        #expect(result.tokens == [1, 7])
        #expect(result.logProbs == [0, -0.1])
    }

    @Test("each returned token carries its own position's runner-ups and keeps its own log-probability")
    func runnerUpsAlignWithTokens() async throws {
        let sampler = EvidenceSampler(wrapping: Scripted(token: 0))
        // A prompt token before the transcript, then two sampled steps.
        let prompt = [1, Self.startOfTranscript]
        _ = await sampler.update(tokens: prompt, logits: try Self.logits([3: 2, 4: 1]), logProbs: [0, 0])
        _ = await sampler.update(
            tokens: prompt + [3], logits: try Self.logits([5: 2, 6: 1.5]), logProbs: [0, 0, 0])
        _ = sampler.finalize(tokens: prompt + [3, 5], logProbs: [0, 0, -0.3, -0.4])
        let result = DecodingResult(
            language: "en", languageProbs: [:], tokens: [Self.startOfTranscript, 3, 5],
            tokenLogProbs: [[Self.startOfTranscript: 0], [3: -0.3], [5: -0.4]], text: "",
            avgLogProb: 0, noSpeechProb: 0, temperature: 0, compressionRatio: 0, cache: nil,
            timings: TranscriptionTimings(), fallback: nil)

        let carried = sampler.tokenLogProbs(of: result)

        #expect(carried.map { Set($0.keys) } == [[Self.startOfTranscript], [3, 4], [5, 6]])
        #expect(carried[1][3] == -0.3)
        #expect(abs((carried[2][6] ?? 0) - (1.5 - log(exp(Float(2)) + exp(1.5)))) < 1e-5)
    }

    /// Spells " ab" as tokens 3 then 5, the one word the bias below helps.
    struct TwoTokenWord: PromptTokenizer {
        let firstSpecialToken = EvidenceSamplerTests.startOfTranscript
        func encode(text: String) -> [Int] { text == " ab" ? [3, 5] : [] }
    }

    @Test("a word the bias pushed reports the confidence the audio alone gave it")
    func biasedWordKeepsItsUnbiasedConfidence() async throws {
        let bias = PhraseBias(words: ["ab"], using: TwoTokenWord(), strength: 2)
        let filter = PhraseBiasFilter(bias: bias, sampleBegin: 2, firstSpecialToken: Self.startOfTranscript)
        let sampler = EvidenceSampler(wrapping: Scripted(token: 5), bias: filter)
        let prompt = [1, Self.startOfTranscript]
        _ = await sampler.update(tokens: prompt, logits: try Self.logits([3: 2, 4: 1]), logProbs: [0, 0])
        // The model prefers 6; the bias lifts continuation 5 over it.
        let raised = filter.filterLogits(try Self.logits([5: 1, 6: 1.5]), withTokens: prompt + [3])
        #expect(raised[5].floatValue == 3)
        _ = await sampler.update(tokens: prompt + [3], logits: raised, logProbs: [0, 0, 0])
        _ = sampler.finalize(tokens: prompt + [3, 5], logProbs: [0, 0, -0.3, -0.1])
        let result = DecodingResult(
            language: "en", languageProbs: [:], tokens: [Self.startOfTranscript, 3, 5],
            tokenLogProbs: [[Self.startOfTranscript: 0], [3: -0.3], [5: -0.1]], text: "",
            avgLogProb: 0, noSpeechProb: 0, temperature: 0, compressionRatio: 0, cache: nil,
            timings: TranscriptionTimings(), fallback: nil)

        let carried = sampler.tokenLogProbs(of: result)

        let unbiased = 1 - log(exp(Float(1)) + exp(1.5))
        #expect(abs((carried[2][5] ?? 0) - unbiased) < 1e-5)
        #expect(abs((carried[2][6] ?? 0) - (1.5 - log(exp(Float(1)) + exp(1.5)))) < 1e-5)
        #expect(carried[1][3] == -0.3)
    }

    @Test("the scores are the vocabulary only, never the padding stored past it")
    func scoresStopAtTheVocabulary() throws {
        let logits = try Self.padded([0, 1, 2], padding: 5, filler: 99)

        #expect(TokenLeaders.scores(of: logits) == [0, 1, 2])
    }

    @Test("entropy is that of the softmax over the finite scores")
    func entropyOfScores() throws {
        let uniform = try #require(TokenLeaders.entropy(of: [1, 1, -.infinity, 1, 1]))
        #expect(abs(uniform - log(4)) < 1e-5)
        #expect(TokenLeaders.entropy(of: [0, -.infinity]) == 0)
        #expect(TokenLeaders.entropy(of: [-.infinity]) == nil)
    }

    @Test("each returned token carries the entropy of its own step in the window record")
    func entropiesAlignWithTokens() async throws {
        let sampler = EvidenceSampler(wrapping: Scripted(token: 0))
        let prompt = [1, Self.startOfTranscript]
        _ = await sampler.update(tokens: prompt, logits: try Self.logits([3: 2, 4: 2]), logProbs: [0, 0])
        _ = await sampler.update(tokens: prompt + [3], logits: try Self.logits([5: 2]), logProbs: [0, 0, 0])
        _ = sampler.finalize(tokens: prompt + [3, 5], logProbs: [0, 0, -0.3, -0.4])
        let result = DecodingResult(
            language: "en", languageProbs: [:], tokens: [Self.startOfTranscript, 3, 5],
            tokenLogProbs: [[Self.startOfTranscript: 0], [3: -0.3], [5: -0.4]], text: "",
            avgLogProb: 0, noSpeechProb: 0, temperature: 0.2, compressionRatio: 0, cache: nil,
            timings: TranscriptionTimings(), fallback: nil)

        let window = sampler.window(of: result)

        #expect(window.tokens == [Self.startOfTranscript, 3, 5])
        #expect(window.entropies.count == 3)
        #expect(window.entropies[0] == nil)
        #expect(abs((window.entropies[1] ?? 0) - log(2)) < 1e-5)
        #expect(window.entropies[2] == 0)
        #expect(window.temperature == 0.2)
    }

    @Test("the window log drains in order and keeps at most its capacity")
    func windowLogIsBounded() {
        let log = DecodeWindowLog()
        for index in 0...DecodeWindowLog.capacity {
            log.append(DecodeWindowEvidence(tokens: [index], entropies: [nil], temperature: 0))
        }

        let drained = log.drain()

        #expect(drained.count == DecodeWindowLog.capacity)
        #expect(drained.first?.tokens == [1])
        #expect(log.drain().isEmpty)
    }
}
