import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("A dictation's screen-text reason")
struct ScreenTextReasonRecordingTests {
    /// Runs one dictation reading `screen`, and says what reached the recorder.
    private func recorded(reading screen: AppContext) async -> [ContextUnavailableReason?] {
        let metrics = RecordingMetricsRecorder()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: FakeSpeechEngine(transcribeOutcome: .success(Transcription(text: "what I said"))),
            cleaner: FakeTranscriptCleaner(), context: FakeContextEngine(context: screen),
            inserter: FakeTextInserter(), metrics: metrics)
        await pipeline.startRecording()
        await pipeline.finishRecording()
        return await metrics.screenText
    }

    @Test("reaches the recorder as the read named it", arguments: ContextUnavailableReason.allCases)
    func reasonIsRecorded(_ reason: ContextUnavailableReason) async {
        let screen = AppContext(
            applicationName: "Notes", bundleIdentifier: "com.example.notes", unavailable: reason)
        #expect(await recorded(reading: screen) == [reason])
    }

    @Test("is absent for an empty field, which the read did reach")
    func emptyFieldHasNoReason() async {
        let screen = AppContext(
            applicationName: "Notes", bundleIdentifier: "com.example.notes", precedingText: "")
        #expect(await recorded(reading: screen) == [nil])
    }
}
