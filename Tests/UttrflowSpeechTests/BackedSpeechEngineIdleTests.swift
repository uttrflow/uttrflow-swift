// Tests that the engine lets an idle recogniser go and loads it again when asked.
import Testing

@testable import UttrflowCore
@testable import UttrflowSpeech

@Suite("BackedSpeechEngine idle release")
struct BackedSpeechEngineIdleTests {
    private func audio(seconds: Double) -> AudioSamples {
        .canonical(Array(repeating: 0.1, count: Int(Double(AudioSamples.canonicalSampleRate) * seconds)))
    }

    @Test("an engine with no idle window never lets the recogniser go")
    func holdsWithoutWindow() async throws {
        let backend = FakeTranscriptionBackend()
        let engine = BackedSpeechEngine(kind: .whisperKit, backend: backend)
        try await engine.prepare()
        #expect(await engine.watching == nil)
        #expect(await engine.holdsTheRecogniser)
    }

    @Test("lets the recogniser go once idle, and loads it again for the next dictation")
    func releasesWhenIdleAndReloads() async throws {
        let backend = FakeTranscriptionBackend()
        let engine = BackedSpeechEngine(kind: .whisperKit, backend: backend, idleAfter: .milliseconds(20))
        try await engine.prepare()
        await engine.watching?.value

        #expect(backend.unloadCount == 1)
        #expect(await !engine.holdsTheRecogniser)

        _ = try await engine.transcribe(audio(seconds: 1), options: TranscriptionOptions())
        #expect(backend.loadCount == 2)
        #expect(await engine.holdsTheRecogniser)
    }

    @Test("release lets the recogniser go at once and a later prepare loads it again")
    func releaseOnDemand() async throws {
        let backend = FakeTranscriptionBackend()
        let engine = BackedSpeechEngine(kind: .whisperKit, backend: backend, idleAfter: .seconds(600))
        try await engine.prepare()
        await engine.release()
        await engine.release()

        #expect(backend.unloadCount == 1)
        #expect(await engine.watching == nil)
        try await engine.prepare()
        #expect(backend.loadCount == 2)
    }

    @Test("warm loads the recogniser without the caller waiting on it")
    func warmLoads() async throws {
        let backend = FakeTranscriptionBackend()
        let engine = BackedSpeechEngine(kind: .whisperKit, backend: backend)
        await engine.warm()
        await engine.warming?.value
        await engine.warm()

        #expect(backend.loadCount == 1)
        #expect(await engine.holdsTheRecogniser)
    }
}
