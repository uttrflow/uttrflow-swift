import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// A recogniser that names each call in order and can be told to hear nothing on some.
private actor NumberingSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private(set) var sampleCounts: [Int] = []
    private var silentCalls: Set<Int>
    private var failingCalls: Set<Int>

    init(silentCalls: Set<Int> = [], failingCalls: Set<Int> = []) {
        self.silentCalls = silentCalls
        self.failingCalls = failingCalls
    }

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        sampleCounts.append(audio.samples.count)
        let call = sampleCounts.count
        if silentCalls.contains(call) { throw .nothingHeard }
        if failingCalls.contains(call) { throw .transcriptionFailed(description: "call \(call)") }
        return Transcription(
            text: "w\(call) x", detectedLanguage: DetectedLanguage(code: .english, confidence: 1),
            audioDuration: audio.duration)
    }

    var calls: Int { sampleCounts.count }
}

/// A tidier that shouts, so its work on each piece can be seen, and remembers being warmed.
private final class ShoutingCleaner: TranscriptCleaning, Sendable {
    private let state = Mutex((warmed: 0, seen: [String]()))
    private let failOn: String?

    init(failOn: String? = nil) {
        self.failOn = failOn
    }

    func clean(_ request: TransformationRequest) async throws(TransformationError) -> TransformationResult {
        let text = request.transcription.text
        state.withLock { $0.seen.append(text) }
        if let failOn, text.contains(failOn) { throw .outputRejected(reason: "scripted") }
        return TransformationResult(text: text.uppercased(), producedBy: .foundationModels)
    }

    func warm() async {
        state.withLock { $0.warmed += 1 }
    }

    var warmed: Int { state.withLock(\.warmed) }
    var seen: [String] { state.withLock(\.seen) }
}

private final class CollectingInserter: TextInserting, Sendable {
    private let received = Mutex<[String]>([])

    func insert(_ text: String) async throws(TextInsertionError) -> TextInsertionMethod {
        received.withLock { $0.append(text) }
        return .accessibility
    }

    var texts: [String] { received.withLock { $0 } }
}

/// A dictionary that rewrites the first word of whatever it is shown.
private struct FirstWordCorrector: WordCorrecting {
    let entry = UUID()

    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> [DictationCorrection] {
        let first = transcription.text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return [
            DictationCorrection(
                heard: first, wrote: first.uppercased(), wordRange: 0..<1, entryID: entry,
                reason: "test", heardConfidence: 0.1)
        ]
    }
}

/// Recordings with pauses where the windowing below expects them.
private enum Take {
    static let rate = AudioSamples.canonicalSampleRate

    static func tone(_ seconds: Double) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { 0.3 * Float(sin(Double($0) * 0.07)) }
    }

    static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * Double(rate)))
    }

    /// Three phrases with a clear pause after the first two.
    static let threePieces = AudioSamples.canonical(
        tone(1.2) + silence(0.5) + tone(1.2) + silence(0.5) + tone(0.4))
}

/// Windows short enough for a test recording to have several.
private let quick = SpeechWindowing(
    minimumLength: 1, sentencePause: 0.3, comfortableLength: 2, anyPause: 0.2, maximumLength: 5)

extension DictationState {
    fileprivate var outcome: DictationOutcome? {
        if case .inserted(let outcome) = self { outcome } else { nil }
    }

    fileprivate var failure: DictationFailure? {
        if case .failed(let failure) = self { failure } else { nil }
    }
}

// MARK: - Tests

@Suite("Dictation pipeline: working ahead while the key is held")
struct DictationPipelineEarlyWorkTests {
    private func makePipeline(
        capture: FakeAudioCaptureEngine,
        speech: NumberingSpeechEngine = NumberingSpeechEngine(),
        cleaner: ShoutingCleaner = ShoutingCleaner(),
        inserter: CollectingInserter = CollectingInserter(),
        context: FakeContextEngine = FakeContextEngine(context: .fixture()),
        corrector: any WordCorrecting = NoTextChanges(),
        metrics: any MetricsRecording = NoOpMetricsRecorder(),
        recordings: any RecordingKeeper = RecordingsNotKept()
    ) -> DictationPipeline {
        DictationPipeline(
            capture: capture, speech: speech, cleaner: cleaner, context: context,
            inserter: inserter, corrector: corrector, metrics: metrics, recordings: recordings,
            windowing: quick, earlyPoll: .milliseconds(2))
    }

    /// Waits for the recogniser to have been asked `count` times, or gives up loudly.
    private func waitForCalls(_ count: Int, on speech: NumberingSpeechEngine) async {
        for _ in 0..<2000 where await speech.calls < count {
            try? await Task.sleep(for: .milliseconds(2))
        }
        #expect(await speech.calls >= count, "the recogniser was never asked \(count) times")
    }

    @Test("pieces ended by a pause are recognised and tidied before the key is released")
    func worksAheadWhileRecording() async {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let speech = NumberingSpeechEngine()
        let cleaner = ShoutingCleaner()
        let inserter = CollectingInserter()
        let pipeline = makePipeline(capture: capture, speech: speech, cleaner: cleaner, inserter: inserter)

        await pipeline.startRecording()
        await waitForCalls(2, on: speech)
        #expect(await pipeline.currentState == .recording)
        #expect(cleaner.seen.count >= 1, "the first piece is tidied while recording")
        await pipeline.finishRecording()

        let state = await pipeline.currentState
        #expect(state.outcome?.text == "W1 X W2 X W3 X")
        #expect(state.outcome?.cleanedBy == .foundationModels)
        #expect(await speech.calls == 3)
        let counts = await speech.sampleCounts
        #expect(
            counts.reduce(0, +) == Take.threePieces.samples.count,
            "every sample goes to the recogniser once")
        #expect(cleaner.warmed == 1)
    }

    @Test("the screen read while recording names where the words went")
    func earlyContextNamesTheApp() async {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let speech = NumberingSpeechEngine()
        let context = FakeContextEngine(context: .fixture(applicationName: "Notes"))
        let pipeline = makePipeline(capture: capture, speech: speech, context: context)

        await pipeline.startRecording()
        await waitForCalls(1, on: speech)
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.outcome?.insertedInto == "Notes")
        #expect(await context.calls.count == 1, "one read serves every piece")
    }

    @Test("pieces cut from audio the stop did not return are thrown away, not joined")
    func mismatchedAudioStartsOver() async {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 0.5)))
        await capture.setCaptured(Take.threePieces)
        let speech = NumberingSpeechEngine()
        let pipeline = makePipeline(capture: capture, speech: speech)

        await pipeline.startRecording()
        await waitForCalls(2, on: speech)
        await pipeline.finishRecording()

        let state = await pipeline.currentState
        let calls = await speech.calls
        #expect(state.outcome?.text == "W\(calls) X", "the returned audio is recognised whole")
    }

    @Test("cancelling while a piece is under way inserts nothing")
    func cancelDropsEarlyPieces() async {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let speech = NumberingSpeechEngine()
        let inserter = CollectingInserter()
        let pipeline = makePipeline(capture: capture, speech: speech, inserter: inserter)

        await pipeline.startRecording()
        await waitForCalls(1, on: speech)
        await pipeline.cancel()
        await pipeline.finishRecording()

        #expect(await pipeline.currentState == .idle)
        #expect(inserter.texts.isEmpty)
    }

    @Test("a piece that fails while recording is left for the end, where its failure is reported")
    func earlyFailureIsReportedAtTheEnd() async {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let speech = NumberingSpeechEngine(failingCalls: [1, 2])
        let pipeline = makePipeline(capture: capture, speech: speech)

        await pipeline.startRecording()
        await waitForCalls(1, on: speech)
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.failure != nil)
        #expect(await speech.calls == 2, "the failed piece is tried once more at the end, not skipped")
    }

    @Test("a retried recording is recognised in windows, so a long one is never one request")
    func retryUsesWindows() async {
        let recording = KeptRecording(id: UUID(), when: Date(), duration: .seconds(3))
        let recordings = FakeRecordingKeeper(
            waiting: [recording], audioOutcome: .success(Take.threePieces))
        let speech = NumberingSpeechEngine()
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(), speech: speech, recordings: recordings)

        await pipeline.retry(recording.id)

        let state = await pipeline.currentState
        #expect(state.outcome?.text == "W1 X W2 X W3 X")
        #expect(state.outcome?.isFromRecording == true)
        #expect(await speech.calls == 3)
    }

    @Test("a window with nothing in it is skipped, and the rest are joined")
    func silentWindowIsSkipped() async {
        let speech = NumberingSpeechEngine(silentCalls: [2])
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces)), speech: speech)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.outcome?.text == "W1 X W3 X")
    }

    @Test("a recording with nothing in any window is refused as silence")
    func allSilentIsRefused() async {
        let speech = NumberingSpeechEngine(silentCalls: [1, 2, 3])
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces)), speech: speech)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await pipeline.currentState == .failed(DictationFailure(SpeechEngineError.nothingHeard)))
    }

    @Test("corrections keep pointing at their words after the pieces are joined")
    func correctionsAreShifted() async {
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces)),
            corrector: FirstWordCorrector())

        await pipeline.startRecording()
        await pipeline.finishRecording()

        let outcome = await pipeline.currentState.outcome
        #expect(outcome?.text == "W1 X W2 X W3 X")
        #expect(outcome?.changes.corrections.map(\.wordRange) == [0..<1, 2..<3, 4..<5])
        #expect(outcome?.changes.spokenWords == 6)
    }

    @Test("one piece the model left to the rules makes the whole a rules result")
    func mixedTidyingReportsRules() async {
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces)),
            cleaner: ShoutingCleaner(failOn: "w2"))

        await pipeline.startRecording()
        await pipeline.finishRecording()

        let outcome = await pipeline.currentState.outcome
        #expect(outcome?.text == "W1 X w2 x W3 X")
        #expect(outcome?.cleanedBy == .rules)
    }

    @Test("a dictation done in pieces still reports one figure per stage")
    func metricsAreOnePerStage() async {
        let metrics = RecordingMetricsRecorder()
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces)), metrics: metrics)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await metrics.measurements(for: .transcription).count == 1)
        #expect(await metrics.measurements(for: .transformation).count == 1)
        #expect(await metrics.measurements(for: .insertion).count == 1)
    }

    @Test("nothing recorded at all still reaches the recogniser, whose refusal names the reason")
    func emptyRecordingIsRefusedByTheRecogniser() async {
        let speech = NumberingSpeechEngine(silentCalls: [1])
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.empty)), speech: speech)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await speech.calls == 1)
        #expect(await pipeline.currentState == .failed(DictationFailure(SpeechEngineError.nothingHeard)))
    }
}
