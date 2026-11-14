// Tests that a dictation hands its piece trace to a recorder that wants one, and never for a secure field.
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A tidier that leaves the words alone.
private struct UntouchedCleaner: TranscriptCleaning {
    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        TransformationResult(text: request.transcription.text, producedBy: .rules)
    }
}

/// Keeps every trace it is handed while `tracesDictations` is set.
private final class TraceKeeper: CleaningRecording, DictationTraceRecording {
    let tracesDictations: Bool
    private let kept = Mutex<[[String]]>([])

    init(on: Bool) { tracesDictations = on }

    func record(_ record: CleaningRecord) async {}
    func recordTrace(_ lines: [String]) { kept.withLock { $0.append(lines) } }
    var traces: [[String]] { kept.withLock { $0 } }
}

private func dictate(seeing context: AppContext, into keeper: TraceKeeper) async -> DictationState {
    let pipeline = DictationPipeline(
        capture: FakeAudioCaptureEngine(),
        speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: "send the draft"))),
        cleaner: UntouchedCleaner(),
        context: FakeContextEngine(context: context),
        inserter: FakeTextInserter(.success(InsertionAttempt(.accessibility))),
        cleaningRecorder: keeper,
        clock: ManualClock())
    await pipeline.startRecording()
    await pipeline.finishRecording()
    return await pipeline.currentState
}

@Suite("A dictation hands its trace to a recorder only while tracing is on")
struct DictationTraceOutcomeTests {
    @Test("the trace names the piece and ends on the inserted words")
    func traceIsRecorded() async throws {
        let keeper = TraceKeeper(on: true)
        let state = await dictate(seeing: AppContext(applicationName: "Notes"), into: keeper)
        guard case .inserted(let outcome) = state else {
            Issue.record("the dictation was not inserted")
            return
        }
        let trace = try #require(keeper.traces.first)
        #expect(keeper.traces.count == 1)
        #expect(trace.first?.hasPrefix("piece 1") == true)
        #expect(trace.last?.hasPrefix("result") == true)
        #expect(trace.last?.hasSuffix(outcome.text) == true)
    }

    @Test("with tracing off nothing is handed over")
    func offRecordsNothing() async {
        let keeper = TraceKeeper(on: false)
        _ = await dictate(seeing: AppContext(applicationName: "Notes"), into: keeper)
        #expect(keeper.traces.isEmpty)
    }

    @Test("a secure field's dictation hands over no trace")
    func secureFieldHasNone() async {
        let keeper = TraceKeeper(on: true)
        _ = await dictate(
            seeing: AppContext(applicationName: "Keychain Access", isSecure: true), into: keeper)
        #expect(keeper.traces.isEmpty)
    }
}
