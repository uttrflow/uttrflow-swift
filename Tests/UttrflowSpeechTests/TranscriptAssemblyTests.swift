// Regression tests for the pure transcript decisions used by both recognisers.
import Testing

@testable import UttrflowCore
@testable import UttrflowSpeech

@Suite("Recovering an empty vocabulary-biased decode")
struct EmptyPromptRetryTests {
    @Test("retries once without vocabulary and returns its text and combined effort")
    func retriesAnEmptyBiasedDecode() async throws {
        let biasedEffort = DecodeEffort(fallbacks: 1, fallbackSeconds: 0.25, encoderRuns: 2)
        let retryEffort = DecodeEffort(fallbacks: 2, fallbackSeconds: 0.5, encoderRuns: 3)
        let backend = EmptyPromptRetryBackend([
            RawTranscript(text: "", effort: biasedEffort, vocabularyPrompt: ["Uttrflow"]),
            RawTranscript(text: "recovered words", languageIdentifier: "en", effort: retryEffort),
        ])

        let transcript = try await CappedDecodeRetry.transcribeRecoveringEmptyPrompt(
            samples: [0.1, 0.2], languageHint: .english, vocabulary: ["Uttrflow"], using: backend)

        #expect(transcript.text == "recovered words")
        #expect(
            transcript.effort
                == DecodeEffort(
                    fallbacks: 3, fallbackSeconds: 0.75, encoderRuns: 5, retriedWithoutPrompt: true))
        #expect(transcript.vocabularyPrompt.isEmpty)
        #expect(await backend.calls == [["Uttrflow"], []])
    }

    @Test("does not retry an empty result when vocabulary is empty")
    func doesNotRetryWithoutVocabulary() async throws {
        let backend = EmptyPromptRetryBackend([RawTranscript(text: "")])

        let transcript = try await CappedDecodeRetry.transcribeRecoveringEmptyPrompt(
            samples: [0.1], languageHint: nil, vocabulary: [], using: backend)

        #expect(transcript.text.isEmpty)
        #expect(await backend.calls == [[]])
    }

    @Test("keeps a non-empty biased result without retrying")
    func keepsNonEmptyBiasedResult() async throws {
        let expected = RawTranscript(
            text: "heard words", languageIdentifier: "en", vocabularyPrompt: ["Uttrflow"])
        let backend = EmptyPromptRetryBackend([expected])

        let transcript = try await CappedDecodeRetry.transcribeRecoveringEmptyPrompt(
            samples: [0.1], languageHint: .english, vocabulary: ["Uttrflow"], using: backend)

        #expect(transcript == expected)
        #expect(await backend.calls == [["Uttrflow"]])
    }
}

@Suite("Assembling recogniser output")
struct TranscriptAssemblyTests {
    @Test("flattens WhisperKit windows in order and sums tokens and effort")
    func flattensWhisperWindows() {
        let firstWord = RawWord(text: " hello", start: 0.1, end: 0.5, probability: 0.91)
        let secondWord = RawWord(text: " there", start: 1.1, end: 1.6, probability: 0.87)
        let windows = [
            WhisperTranscriptWindow(
                text: "hello", languageIdentifier: "en",
                segments: [RawSegment(text: "hello", start: 0, end: 0.6, words: [firstWord])],
                effort: DecodeEffort(fallbacks: 1, fallbackSeconds: 0.25, encoderRuns: 2),
                tokensUsed: 4, promptPositions: 3, vocabularyPrompt: ["Uttrflow"]),
            WhisperTranscriptWindow(
                text: "there", languageIdentifier: "hi",
                segments: [RawSegment(text: "there", start: 1, end: 1.8, words: [secondWord])],
                effort: DecodeEffort(fallbacks: 2, fallbackSeconds: 0.5, encoderRuns: 3),
                tokensUsed: 6, promptPositions: 3, vocabularyPrompt: ["Uttrflow"]),
        ]

        let transcript = TranscriptAssembly.whisper(windows)

        #expect(transcript.text == "hello there")
        #expect(transcript.languageIdentifier == "en")
        #expect(transcript.segments == windows.flatMap(\.segments))
        #expect(transcript.segments.map(\.start) == [0, 1])
        #expect(transcript.segments.flatMap { $0.words ?? [] } == [firstWord, secondWord])
        #expect(transcript.segments.flatMap { $0.words ?? [] }.map(\.end) == [0.5, 1.6])
        #expect(transcript.tokensUsed == 10)
        #expect(transcript.promptPositions == 3)
        #expect(transcript.vocabularyPrompt == ["Uttrflow"])
        #expect(transcript.effort == DecodeEffort(fallbacks: 3, fallbackSeconds: 0.75, encoderRuns: 5))
    }

    @Test("drops interim Apple results and joins final results")
    func joinsFinalAppleResults() {
        let first = RawSegment(text: "first", start: 0, end: 0.5)
        let second = RawSegment(text: "second", start: 0.6, end: 1)
        let pieces = [
            FinalTranscriptPiece(text: "partial", isFinal: false),
            FinalTranscriptPiece(text: "first", isFinal: true, segment: first),
            FinalTranscriptPiece(text: "another partial", isFinal: false),
            FinalTranscriptPiece(text: "second", isFinal: true, segment: second),
        ]

        #expect(TranscriptAssembly.finalText(from: pieces) == "first second")
        let assembled = TranscriptAssembly.apple(from: pieces)
        #expect(assembled.text == "first second")
        #expect(assembled.segments == [first, second])
    }

    @Test("chunks every sample once and keeps the short final chunk")
    func chunksAudio() {
        let samples = [0, 1, 2, 3, 4, 5, 6]

        #expect(samples.chunked(into: 3) == [[0, 1, 2], [3, 4, 5], [6]])
        #expect(samples.chunked(into: 3).flatMap { $0 } == samples)
        #expect([Int]().chunked(into: 3).isEmpty)
    }
}

private actor EmptyPromptRetryBackend: TranscriptionBackend {
    let minimumDuration: Duration = .zero
    private var results: [RawTranscript]
    private(set) var calls: [[String]] = []

    init(_ results: [RawTranscript]) {
        self.results = results
    }

    func load() async throws(SpeechEngineError) {}

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?
    ) async throws(SpeechEngineError) -> RawTranscript {
        try await transcribe(samples, languageHint: languageHint, biasedTowards: [])
    }

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?, biasedTowards vocabulary: [String]
    ) async throws(SpeechEngineError) -> RawTranscript {
        calls.append(vocabulary)
        return results.removeFirst()
    }
}
