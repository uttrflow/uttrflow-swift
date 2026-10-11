// Tests that a transcription reports the time it waited for the recogniser to load.
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowSpeech
import UttrflowTestSupport

@Suite("BackedSpeechEngine load time")
struct BackedSpeechEngineLoadTimeTests {
    private func audio(seconds: Double) -> AudioSamples {
        // A tone, not a constant level: loudness is measured about the frame's mean, so a DC level is silence.
        let count = Int(Double(AudioSamples.canonicalSampleRate) * seconds)
        return .canonical((0..<count).map { 0.1 * Float(sin(Double($0) * 0.07)) })
    }

    /// An engine whose every load takes `load` on a clock that only the load moves.
    private func engine(loadTaking load: Duration) -> BackedSpeechEngine {
        let clock = ManualClock()
        return BackedSpeechEngine(
            kind: .whisperKit, backend: FakeTranscriptionBackend(), clock: clock,
            willLoad: { clock.advance(by: load) })
    }

    @Test("a transcription that loads the recogniser reports the load's time")
    func coldTranscriptionReportsLoad() async throws {
        let engine = engine(loadTaking: .seconds(3))

        let heard = try await engine.transcribe(audio(seconds: 1), options: .automatic)

        #expect(heard.effort.loadSeconds == 3)
        #expect(heard.effort.namedSeconds == 3)
    }

    @Test("a transcription on a recogniser loaded before it reports no load")
    func warmTranscriptionReportsNoLoad() async throws {
        let engine = engine(loadTaking: .seconds(3))
        try await engine.prepare()

        let heard = try await engine.transcribe(audio(seconds: 1), options: .automatic)

        #expect(heard.effort.loadSeconds == 0)
        #expect(heard.effort == .none)
    }
}
