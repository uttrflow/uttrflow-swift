// Tests that the vocabulary bias follows one stated rule on every decode path of a piece.
import Testing

@testable import UttrflowCore
@testable import UttrflowSpeech

/// Records the vocabulary and the text before the caret that each call's bias and prompt are built from.
private actor BiasRecordingBackend: TranscriptionBackend {
    let minimumDuration: Duration = .zero
    private var results: [RawTranscript]
    private(set) var seen: [[String]] = []
    private(set) var preceding: [String?] = []

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
        try await transcribe(samples, languageHint: languageHint, biasedTowards: vocabulary, after: nil)
    }

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?, biasedTowards vocabulary: [String],
        after precedingText: String?
    ) async throws(SpeechEngineError) -> RawTranscript {
        seen.append(vocabulary)
        preceding.append(precedingText)
        return results.removeFirst()
    }
}

@Suite("DecodeBias")
struct DecodeBiasTests {
    private let words = ["Uttrflow", "Zoltan"]
    private let samples = [Float](repeating: 0.1, count: 16_000)

    @Test("same keeps the prompt and the words, and none drops both but keeps the language")
    func rule() {
        let first = TranscriptionOptions(languageHint: .hindi, vocabulary: words, precedingText: "Hello.")
        #expect(DecodeBias.same.options(first) == first)
        #expect(DecodeBias.none.options(first) == TranscriptionOptions(languageHint: .hindi))
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
        #expect(await backend.preceding == ["Hello", nil])
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
