// Tests that a piece decoded a second time names that second decode as the dictation's slow cause.
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
import UttrflowTestSupport

@Suite("Naming a second decode in the wait")
struct DictationRetryWaitTests {
    @Test("a speech-bearing piece decoded again names the second decode, less its fallbacks, as the retry")
    func secondDecodeIsTheRetry() async {
        let clock = ManualClock()
        let metrics = RecordingMetricsRecorder()
        // One window heard twice: no words in the first decode, words in the second, each costing its time.
        let scenario = Scenario(
            pieces: [
                ScriptedPiece("", decodeTime: .seconds(1)),
                ScriptedPiece(
                    "what I said", decodeTime: .seconds(6),
                    effort: DecodeEffort(fallbacks: 1, fallbackSeconds: 1)),
            ],
            context: .unknown, cleaner: FakeTranscriptCleaner(), take: ScenarioDriver.oneWindow,
            metrics: metrics, clock: clock)

        _ = await ScenarioDriver.run(scenario)

        #expect(await metrics.decoding.map(\.retrySeconds) == [5])
        #expect(await metrics.waits.map(\.cause) == [.cappedDecodeRetry])
        #expect(await metrics.waits.first?.wait.spent[.cappedDecodeRetry] == .seconds(5))
    }
}
