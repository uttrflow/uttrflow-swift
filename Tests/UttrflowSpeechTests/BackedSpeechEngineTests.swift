import Testing

@testable import UttrflowCore
@testable import UttrflowSpeech

@Suite("BackedSpeechEngine")
struct BackedSpeechEngineTests {
    private func engine(
        _ backend: FakeTranscriptionBackend, kind: SpeechEngineKind = .whisperKit
    ) -> BackedSpeechEngine {
        BackedSpeechEngine(kind: kind, backend: backend)
    }

    private func audio(seconds: Double) -> AudioSamples {
        .canonical(Array(repeating: 0.1, count: Int(Double(AudioSamples.canonicalSampleRate) * seconds)))
    }

    @Test("reports the recogniser it was built with", arguments: SpeechEngineKind.allCases)
    func reportsKind(kind: SpeechEngineKind) {
        #expect(engine(FakeTranscriptionBackend(), kind: kind).kind == kind)
    }

    @Test("loads the recogniser once, however often prepare is called")
    func loadsOnce() async throws {
        let backend = FakeTranscriptionBackend()
        let engine = engine(backend)

        try await engine.prepare()
        try await engine.prepare()
        try await engine.prepare()

        #expect(backend.loadCount == 1)
    }

    @Test("surfaces a load failure and stays unloaded, so a retry can work")
    func loadFailureIsRetryable() async {
        let backend = FakeTranscriptionBackend()
        backend.failLoad(with: .modelNotInstalled)
        let engine = engine(backend)

        await #expect(throws: SpeechEngineError.modelNotInstalled) { try await engine.prepare() }
        await #expect(throws: SpeechEngineError.modelNotInstalled) { try await engine.prepare() }
        #expect(backend.loadCount == 2, "a failed load must be attempted again")
    }

    @Test("loads on demand when a caller forgets to prepare")
    func transcribeLoadsOnDemand() async throws {
        let backend = FakeTranscriptionBackend()
        let engine = engine(backend)

        _ = try await engine.transcribe(audio(seconds: 1), options: .automatic)
        #expect(backend.loadCount == 1)
    }

    @Test("does not load twice when prepare ran first")
    func prepareThenTranscribe() async throws {
        let backend = FakeTranscriptionBackend()
        let engine = engine(backend)

        try await engine.prepare()
        _ = try await engine.transcribe(audio(seconds: 1), options: .automatic)

        #expect(backend.loadCount == 1)
    }

    /// Recognisers hallucinate confidently on a fraction of a second of noise, so the
    /// engine refuses rather than passing it on.
    @Test("refuses audio too short to carry a word", arguments: [0.0, 0.05, 0.2, 0.249])
    func refusesTooShortAudio(seconds: Double) async {
        let backend = FakeTranscriptionBackend()
        let engine = engine(backend)

        await #expect(throws: SpeechEngineError.audioTooShort) {
            try await engine.transcribe(audio(seconds: seconds), options: .automatic)
        }
        #expect(backend.calls.isEmpty, "the recogniser must not even be asked")
        #expect(backend.loadCount == 0, "and must not be loaded for audio we will not use")
    }

    @Test("accepts audio at exactly the minimum length")
    func acceptsMinimumLength() async throws {
        let backend = FakeTranscriptionBackend()
        _ = try await engine(backend).transcribe(audio(seconds: 0.25), options: .automatic)
        #expect(backend.calls.count == 1)
    }

    @Test("passes the caller's language hint through untouched")
    func passesLanguageHint() async throws {
        let backend = FakeTranscriptionBackend()
        let engine = engine(backend)

        _ = try await engine.transcribe(
            audio(seconds: 1), options: TranscriptionOptions(languageHint: .hindi)
        )
        #expect(backend.calls.first?.languageHint == .hindi)
    }

    @Test("asks the recogniser to detect the language when none is given")
    func detectsByDefault() async throws {
        let backend = FakeTranscriptionBackend()
        _ = try await engine(backend).transcribe(audio(seconds: 1), options: .automatic)
        #expect(backend.calls.first?.languageHint == nil)
    }

    @Test("hands over every sample it was given")
    func passesAllSamples() async throws {
        let backend = FakeTranscriptionBackend()
        let audio = audio(seconds: 2)

        _ = try await engine(backend).transcribe(audio, options: .automatic)
        #expect(backend.calls.first?.sampleCount == audio.samples.count)
    }

    @Test("applies the product's own rules to whatever the recogniser returns")
    func mapsResult() async throws {
        let backend = FakeTranscriptionBackend(
            result: RawTranscript(
                text: "[BLANK_AUDIO] hello there",
                languageIdentifier: "en-US",
                languageProbability: 0.88
            )
        )

        let transcription = try await engine(backend).transcribe(audio(seconds: 3), options: .automatic)

        #expect(transcription.text == "hello there")
        #expect(transcription.detectedLanguage?.code == .english)
        #expect(transcription.detectedLanguage?.confidence == 0.88)
        #expect(transcription.audioDuration == audio(seconds: 3).duration)
    }

    @Test("surfaces a recognition failure rather than returning empty text")
    func transcriptionFailure() async {
        let backend = FakeTranscriptionBackend()
        backend.failTranscribe(with: .transcriptionFailed(description: "decode error"))

        await #expect(throws: SpeechEngineError.transcriptionFailed(description: "decode error")) {
            try await engine(backend).transcribe(audio(seconds: 1), options: .automatic)
        }
    }

    // MARK: The user's own words

    @Test("hands the recogniser the words to listen out for")
    func passesVocabulary() async throws {
        let backend = FakeTranscriptionBackend()
        let engine = BackedSpeechEngine(
            kind: .whisperKit, backend: backend,
            vocabulary: FixedVocabulary(["Uttrflow", "Nikhil"]))

        _ = try await engine.transcribe(audio(seconds: 1), options: .automatic)
        #expect(backend.calls.first?.vocabulary == ["Uttrflow", "Nikhil"])
    }

    @Test("asks for the words once per dictation, because the answer moves")
    func readsVocabularyEveryTime() async throws {
        let backend = FakeTranscriptionBackend()
        let source = FixedVocabulary(["Uttrflow"])
        let engine = BackedSpeechEngine(kind: .whisperKit, backend: backend, vocabulary: source)

        _ = try await engine.transcribe(audio(seconds: 1), options: .automatic)
        _ = try await engine.transcribe(audio(seconds: 1), options: .automatic)
        #expect(await source.readings == 2)
    }

    @Test("an engine given no vocabulary biases the recogniser towards nothing")
    func noVocabularySource() async throws {
        let backend = FakeTranscriptionBackend()
        _ = try await engine(backend).transcribe(audio(seconds: 1), options: .automatic)
        #expect(backend.calls.first?.vocabulary == [])
    }

    @Test("a recogniser that cannot be biased still transcribes")
    func unbiasableBackendStillWorks() async throws {
        let backend = UnbiasableBackend()
        let engine = BackedSpeechEngine(
            kind: .appleSpeech, backend: backend, vocabulary: FixedVocabulary(["Uttrflow"]))

        let transcription = try await engine.transcribe(audio(seconds: 1), options: .automatic)

        #expect(transcription.text == "hello there")
        #expect(backend.transcriptions == 1)
    }
}

/// A vocabulary that is whatever a test says it is, counting how often it was asked.
private actor FixedVocabulary: VocabularySource {
    private let words: [String]
    private(set) var readings = 0

    init(_ words: [String]) {
        self.words = words
    }

    func vocabulary() async -> [String] {
        readings += 1
        return words
    }
}
