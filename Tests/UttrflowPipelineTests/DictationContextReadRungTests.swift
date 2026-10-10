import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("The pipeline reports which rung answered each screen read")
struct DictationContextReadRungTests {
    private static let audio = AudioSamples.canonical(
        (0..<24_000).map { 0.3 * Float(sin(Double($0) * 0.07)) })

    private func dictate(in context: AppContext) async -> [ContextRead] {
        let metrics = RecordingMetricsRecorder()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Self.audio)),
            speech: FakeSpeechEngine(),
            cleaner: FakeTranscriptCleaner(),
            context: FakeContextEngine(context: context),
            inserter: FakeTextInserter(),
            metrics: metrics)
        await pipeline.startRecording()
        await pipeline.finishRecording()
        return await metrics.contextReads
    }

    @Test("every read names its rung and application", arguments: ContextReadRung.allCases)
    func reportsTheRung(rung: ContextReadRung) async {
        let context = AppContext(
            bundleIdentifier: "com.example.editor", precedingText: "Dear team", readRung: rung)

        let reads = await dictate(in: context)

        #expect(!reads.isEmpty)
        #expect(reads.allSatisfy { $0.rung == rung && $0.bundleIdentifier == "com.example.editor" })
    }

    @Test("a read without a rung or an application is not counted")
    func skipsUnnamedReads() async {
        let noRung = AppContext(bundleIdentifier: "com.example.editor", unavailable: .timedOut)
        let noApplication = AppContext(readRung: .wholeValue)

        #expect(await dictate(in: noRung).isEmpty)
        #expect(await dictate(in: noApplication).isEmpty)
    }
}
