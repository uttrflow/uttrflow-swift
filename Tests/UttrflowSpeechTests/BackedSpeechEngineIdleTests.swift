// Tests that the engine lets an idle recogniser go and loads it again when asked.
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowSpeech
import UttrflowTestSupport

@Suite("BackedSpeechEngine idle release")
struct BackedSpeechEngineIdleTests {
    private func audio(seconds: Double) -> AudioSamples {
        // A tone, not a constant level: loudness is measured about the frame's mean, so a DC level is silence.
        let count = Int(Double(AudioSamples.canonicalSampleRate) * seconds)
        return .canonical((0..<count).map { 0.1 * Float(sin(Double($0) * 0.07)) })
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

    @Test("reports every idle unload and the lazy reload")
    func reportsReadinessChanges() async throws {
        let backend = FakeTranscriptionBackend()
        let clock = ManualClock()
        let releases = ReadinessCallbackCount()
        let loads = ReadinessCallbackCount()
        let engine = BackedSpeechEngine(
            kind: .whisperKit, backend: backend, idleAfter: .milliseconds(20), clock: clock,
            didRelease: { releases.increment() }, didLoad: { loads.increment() })

        try await engine.prepare()
        await clock.advanceWhenSomethingIsWaiting(by: .milliseconds(20))
        await engine.watching?.value

        #expect(backend.unloadCount == 1)
        #expect(await !engine.holdsTheRecogniser)
        #expect(releases.value == 1)

        _ = try await engine.transcribe(audio(seconds: 1), options: .automatic)
        await engine.release()

        #expect(releases.value == 2)
        #expect(loads.value == 2)
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

/// Thread-safe callback count for engine lifecycle notifications.
private final class ReadinessCallbackCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }
}
