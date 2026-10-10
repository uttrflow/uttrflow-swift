// Every fallback threshold the decoding options configure is judged against a signal that moves.
import CoreML
import Foundation
import Testing
import WhisperKit

@testable import UttrflowSpeech

@Suite("The decode session's fallback signals")
struct DecodeSessionSignalTests {
    static let special = DecodeSessionTests.special

    /// Where the start-of-transcript token is fed in `DecodeSessionTests.opening`.
    static let startOfTranscriptPosition = 0

    static func options() -> DecodingOptions {
        DecodeSessionTests.options {
            $0.noSpeechThreshold = 0.6
            $0.logProbThreshold = -1.0
        }
    }

    @Test("reports a no-speech probability that is high on silence and low on speech")
    func noSpeechVaries() async throws {
        let silent = try await DecodeSessionTests.decode(
            ScriptedDecoder(script: [Self.startOfTranscriptPosition: Self.special.noSpeechToken, 3: 50]),
            options: Self.options())
        let speech = try await DecodeSessionTests.decode(
            ScriptedDecoder(script: [3: 5, 4: 50]), options: Self.options())

        #expect(silent.noSpeechProb > 0.99)
        #expect(speech.noSpeechProb < 0.01)
        #expect(silent.fallback?.fallbackReason == "silence")
        #expect(speech.fallback?.fallbackReason != "silence")
    }

    @Test("reads the no-speech probability before any filter suppresses the token")
    func noSpeechIgnoresFilters() async throws {
        var options = Self.options()
        options.suppressTokens = [Self.special.noSpeechToken]
        options.suppressBlank = true

        let result = try await DecodeSessionTests.decode(
            ScriptedDecoder(script: [Self.startOfTranscriptPosition: Self.special.noSpeechToken, 3: 50]),
            options: options)

        #expect(result.noSpeechProb > 0.99)
    }

    static func session() throws -> DecodeSession {
        let decoder = ScriptedDecoder(script: [:])
        return try DecodeSession(
            decoder: decoder,
            window: .init(
                encoderOutput: try ScriptedDecoder.array([1, 3, 1, 1]),
                inputs: try decoder.prepareDecoderInputs(withPrompt: DecodeSessionTests.opening),
                options: options()))
    }

    @Test("averages log-probabilities over sampled tokens only, so piece length does not dilute it")
    func meanOverSampledTokens() throws {
        let session = try Self.session()
        let forced = Array(repeating: Float(0), count: DecodeSessionTests.opening.count)
        let short = DecodeSession.Progress(tokens: [], logProbs: forced + [-1, -2], nextToken: 0)
        let long = DecodeSession.Progress(
            tokens: [], logProbs: forced + [-1, -2, -1, -2, -1, -2], nextToken: 0)

        #expect(session.sampledMean(of: short) == -1.5)
        #expect(session.sampledMean(of: long) == -1.5)
    }

    @Test("averages to zero when nothing was sampled")
    func meanOfNothing() throws {
        let session = try Self.session()
        let forced = Array(repeating: Float(0), count: DecodeSessionTests.opening.count)

        let progress = DecodeSession.Progress(tokens: [], logProbs: forced, nextToken: 0)

        #expect(session.sampledMean(of: progress) == 0)
    }

    @Test("gives no probability to a token outside the vocabulary")
    func probabilityOutOfRange() throws {
        let logits = try ScriptedDecoder.array([1, 1, 4], dominant: 0)

        #expect(DecodeSession.probability(of: 9, in: logits) == 0)
        #expect(DecodeSession.probability(of: -1, in: logits) == 0)
    }

    /// Each threshold the shipping options configure must have a signal that can cross it.
    @Test("every threshold the shipping options set is judged against a live signal")
    func thresholdsHaveSignals() async throws {
        let shipping = VocabularyPrompt.decodingOptions(languageHint: .english)
        let threshold = try #require(shipping.noSpeechThreshold)
        let silent = try await DecodeSessionTests.decode(
            ScriptedDecoder(script: [Self.startOfTranscriptPosition: Self.special.noSpeechToken, 3: 50]),
            options: Self.options())

        #expect(silent.noSpeechProb > threshold)
        #expect(shipping.logProbThreshold != nil)
    }
}
