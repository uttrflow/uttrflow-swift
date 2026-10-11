// Tests that the vocabulary bias follows one stated rule on every decode path of a piece.
import Testing

@testable import UttrflowCore
@testable import UttrflowSpeech

/// Records the vocabulary, which is what the bias is built from, at each call.
private actor BiasRecordingBackend: TranscriptionBackend {
    let minimumDuration: Duration = .zero
    private var results: [RawTranscript]
    private(set) var seen: [[String]] = []

    init(_ results: [RawTranscript]) { self.results = results }

    func load() async throws(SpeechEngineError) {}

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?
    ) async throws(SpeechEngineError) -> RawTranscript {
        try await transcribe(samples, languageHint: languageHint, biasedTowards: [])
    }

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?, biasedTowards vocabulary: [String]
    ) async throws(SpeechEngineError) -> RawTranscript {
        seen.append(vocabulary)
        return results.removeFirst()
    }
}

@Suite("DecodeBias")
struct DecodeBiasTests {
    private let words = ["Uttrflow", "Zoltan"]
    private let samples = [Float](repeating: 0.1, count: 16_000)

    @Test("same keeps the words and none drops them")
    func rule() {
        #expect(DecodeBias.same.vocabulary(of: words) == words)
        #expect(DecodeBias.none.vocabulary(of: words).isEmpty)
    }

    @Test("a miss is retried without the bias")
    func missDropsTheBias() async throws {
        let backend = BiasRecordingBackend([RawTranscript(text: ""), RawTranscript(text: "ok")])
        _ = try await CappedDecodeRetry.transcribeRecoveringEmptyPrompt(
            samples: samples, languageHint: .english, vocabulary: words, using: backend)
        #expect(await backend.seen == [words, []])
    }

    @Test("a capped decode retries its tail with the same bias")
    func cappedKeepsTheBias() async throws {
        let capped = RawTranscript(
            text: "one two",
            segments: [
                RawSegment(
                    text: "one two", start: 0, end: 0.9,
                    words: [
                        RawWord(text: "one", start: 0, end: 0.4, probability: 0.9),
                        RawWord(text: "two", start: 0.4, end: 0.5, probability: 0.9),
                    ])
            ],
            tokensUsed: CappedDecodeRetry.tokenCapThreshold)
        let backend = BiasRecordingBackend([capped, RawTranscript(text: "three")])
        _ = try await CappedDecodeRetry.transcribe(
            samples: samples, languageHint: .english, vocabulary: words, using: backend)
        #expect(await backend.seen == [words, words])
    }

    @Test("a miss after a capped tail still ends without the bias")
    func missAfterCap() async throws {
        let backend = BiasRecordingBackend([RawTranscript(text: ""), RawTranscript(text: "ok")])
        _ = try await CappedDecodeRetry.transcribeRecoveringEmptyPrompt(
            samples: samples, languageHint: nil, vocabulary: words, precedingText: "Hello", using: backend)
        #expect(await backend.seen == [words, []])
    }

    @Test("the biased words come from the prompt when it carries them, and from the vocabulary otherwise")
    func derivation() {
        let packed = ["Uttrflow"]
        #expect(DecodeBias.words(vocabulary: words, packed: packed, promptWords: true) == packed)
        #expect(DecodeBias.words(vocabulary: words, packed: packed, promptWords: false) == words)
        #expect(DecodeBias.words(vocabulary: [], packed: [], promptWords: true).isEmpty)
    }

    @Test("two calls build their bias from their own words only")
    func callsDoNotShare() {
        let first = DecodeBias.words(vocabulary: ["alpha"], packed: [], promptWords: false)
        let second = DecodeBias.words(vocabulary: ["beta"], packed: [], promptWords: false)
        #expect(first == ["alpha"] && second == ["beta"])
    }
}
