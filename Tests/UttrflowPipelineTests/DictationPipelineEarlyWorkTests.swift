// Tests transcription that starts while the key is still held.
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
    private(set) var biases: [[String]] = []
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
        biases.append(options.vocabulary)
        let call = sampleCounts.count
        if silentCalls.contains(call) { throw .nothingHeard }
        if failingCalls.contains(call) { throw .transcriptionFailed(description: "call \(call)") }
        return Transcription(
            text: "w\(call) x", detectedLanguage: DetectedLanguage(code: .english, confidence: 1),
            audioDuration: audio.duration)
    }

    var calls: Int { sampleCounts.count }
}

/// A tidier that shouts, so its work on each piece can be seen, and remembers where it was warmed for.
private final class ShoutingCleaner: TranscriptCleaning, Sendable {
    private let state = Mutex((warmed: [Destination?](), seen: [String]()))
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

    func warm(for situation: Situation?) async {
        state.withLock { $0.warmed.append(situation?.destination) }
    }

    var warmed: [Destination?] { state.withLock(\.warmed) }
    var seen: [String] { state.withLock(\.seen) }
}

/// Whether a recognition ran beside a tidy, forced by each side waiting for the other rather than hoped for.
private final class StageRendezvous: Sendable {
    private struct State {
        var recognitionsInFlight = 0
        var recognitions = 0
        var besides = 0
    }

    private let state = Mutex(State())

    /// How many recognitions ran in all, which says the pipeline did the work rather than skipped it.
    var recognitions: Int { state.withLock(\.recognitions) }

    /// How many tidies had a recognition beside them, which is the property #186 asks for.
    var tidiesBesideARecognition: Int { state.withLock(\.besides) }

    /// Holds a recognition open until a tidy has noticed it, so a late-scheduled tidy is waited for.
    func recognition<T: Sendable>(waitsForATidy waits: Bool, doing work: () async -> T) async -> T {
        let noticed = state.withLock { state -> Int in
            state.recognitionsInFlight += 1
            state.recognitions += 1
            return state.besides
        }
        // Waits to be noticed rather than for a tidy to be in flight, which a prompt tidy is only briefly.
        if waits { await until(within: .seconds(2)) { $0.besides > noticed } }
        let answer = await work()
        state.withLock { $0.recognitionsInFlight -= 1 }
        return answer
    }

    /// Holds a tidy open until a recognition is running beside it, which a serial pass can never provide.
    func tidy(waitsForARecognition waits: Bool) async {
        guard waits else { return }
        if await until(within: .seconds(2), { $0.recognitionsInFlight > 0 }) {
            state.withLock { $0.besides += 1 }
        }
    }

    /// Polls until the condition holds, answering whether it ever did rather than how long it took.
    @discardableResult
    private func until(within limit: Duration, _ holds: @Sendable (borrowing State) -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        repeat {
            if state.withLock({ holds($0) }) { return true }
            try? await Task.sleep(for: .milliseconds(2))
        } while ContinuousClock.now < deadline
        return false
    }
}

/// A recogniser that will not finish until a tidy is running beside it, where the pipeline allows one.
private actor TimedSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private let rendezvous: StageRendezvous
    private(set) var calls = 0

    init(rendezvous: StageRendezvous) {
        self.rendezvous = rendezvous
    }

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        calls += 1
        let call = calls
        // The first recognition has no tidy before it to run beside, so waiting for one would only spend the limit.
        return await rendezvous.recognition(waitsForATidy: call > 1) {
            Transcription(
                text: "w\(call) x", detectedLanguage: DetectedLanguage(code: .english, confidence: 1),
                audioDuration: audio.duration)
        }
    }
}

/// A tidier that will not finish until a recognition is running beside it, where the pipeline allows one.
private final class TimedCleaner: TranscriptCleaning, Sendable {
    private let rendezvous: StageRendezvous
    private let pieces: Int
    private let calls = Mutex(0)

    init(rendezvous: StageRendezvous, pieces: Int) {
        self.rendezvous = rendezvous
        self.pieces = pieces
    }

    func clean(_ request: TransformationRequest) async throws(TransformationError) -> TransformationResult {
        let call = calls.withLock { calls in
            calls += 1
            return calls
        }
        // The last piece has no recognition left to run beside, so waiting for one would only spend the limit.
        await rendezvous.tidy(waitsForARecognition: call < pieces)
        return TransformationResult(
            text: request.transcription.text.uppercased(), producedBy: .foundationModels)
    }

    func warm(for situation: Situation?) async {}
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
        speech: any SpeechEngine = NumberingSpeechEngine(),
        cleaner: any TranscriptCleaning = ShoutingCleaner(),
        inserter: CollectingInserter = CollectingInserter(),
        context: FakeContextEngine = FakeContextEngine(context: .fixture()),
        corrector: any WordCorrecting = NoTextChanges(),
        metrics: any MetricsRecording = NoOpMetricsRecorder(),
        recordings: any RecordingKeeper = RecordingsNotKept(),
        speechWords: @escaping @Sendable (AppContext) async -> [String] = { _ in [] }
    ) -> DictationPipeline {
        DictationPipeline(
            capture: capture, speech: speech, cleaner: cleaner, context: context,
            inserter: inserter, speechWords: speechWords, corrector: corrector, metrics: metrics,
            recordings: recordings, windowing: quick, earlyPoll: .milliseconds(2))
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
        #expect(cleaner.warmed == [.messaging], "warmed once, for the Slack window the fixture shows")
    }

    /// The screen is read before the tidier is warmed, so the warm-up is for the right place.
    @Test(
        "the tidier is warmed for where the screen says the words are going, and for plain text when it says nothing"
    )
    func warmsForTheDestination() async {
        for (context, destination) in [
            (
                AppContext.fixture(applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode"),
                Destination.codeEditor
            ),
            (AppContext(), .plain),
        ] {
            let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
            await capture.setCaptured(Take.threePieces)
            let speech = NumberingSpeechEngine()
            let cleaner = ShoutingCleaner()
            let engine = FakeContextEngine(context: context)
            let pipeline = makePipeline(capture: capture, speech: speech, cleaner: cleaner, context: engine)

            await pipeline.startRecording()
            await waitForCalls(1, on: speech)
            await pipeline.finishRecording()

            #expect(cleaner.warmed == [destination])
            #expect(await engine.calls.count == 1, "one read serves the warm-up and every piece")
        }
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
        let speech = NumberingSpeechEngine(failingCalls: Set(1...12))
        let pipeline = makePipeline(capture: capture, speech: speech)

        await pipeline.startRecording()
        await waitForCalls(1, on: speech)
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.failure != nil)
        #expect(await speech.calls >= 2, "the failed piece is tried once more at the end, not skipped")
    }

    @Test("a piece that fails while recording does not stop the later pieces being worked ahead")
    func earlyFailureLeavesTheRestWorkingAhead() async {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let speech = NumberingSpeechEngine(failingCalls: [1])
        let pipeline = makePipeline(capture: capture, speech: speech)

        await pipeline.startRecording()
        await waitForCalls(2, on: speech)
        #expect(
            await pipeline.currentState == .recording,
            "the piece after the failed one is worked ahead, not left to the release")
        await pipeline.finishRecording()

        let state = await pipeline.currentState
        #expect(state.outcome?.text == "W3 X W2 X W4 X", "the failed piece is redone in its own place")
        #expect(await speech.calls == 4, "only the failed piece and the tail are left for the end")
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

    /// The contract VocabularySource's own doc comment claims, which the engine used to break. See #180.
    @Test("ranks the dictation's words once, however many pieces it is cut into")
    func ranksTheWordsOncePerDictation() async {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let speech = NumberingSpeechEngine()
        let rankings = Mutex<[AppContext]>([])
        let pipeline = makePipeline(capture: capture, speech: speech) { seeing in
            rankings.withLock { $0.append(seeing) }
            return ["Uttrflow"]
        }

        await pipeline.startRecording()
        await waitForCalls(2, on: speech)
        await pipeline.finishRecording()

        #expect(await speech.calls == 3)
        #expect(rankings.withLock(\.count) == 1, "one ranking, not one per piece")
        #expect(
            await speech.biases == [["Uttrflow"], ["Uttrflow"], ["Uttrflow"]],
            "every piece is biased towards the same words")
        // Ranked against the screen the dictation began on, which is the one the tidier resolves from.
        #expect(rankings.withLock { $0.first?.applicationName } == AppContext.fixture().applicationName)
    }

    /// The release pass overlaps the two stages, which a retry is the plainest case of. See #186.
    @Test("the tidy of one piece runs beside the recognition of the next, and the pieces stay in order")
    func tidyingRunsBesideTheNextRecognition() async {
        let rendezvous = StageRendezvous()
        let recording = KeptRecording(id: UUID(), when: Date(), duration: .seconds(3))
        let recordings = FakeRecordingKeeper(
            waiting: [recording], audioOutcome: .success(Take.threePieces))
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(),
            speech: TimedSpeechEngine(rendezvous: rendezvous),
            cleaner: TimedCleaner(rendezvous: rendezvous, pieces: 3),
            recordings: recordings)

        await pipeline.retry(recording.id)

        #expect(
            await pipeline.currentState.outcome?.text == "W1 X W2 X W3 X",
            "the pieces are joined in the order they were spoken")
        #expect(rendezvous.recognitions == 3)
        // Each stage waits for the other, so a late-scheduled tidy is waited for rather than missed.
        #expect(
            rendezvous.tidiesBesideARecognition == 2,
            "every tidy but the last runs beside the next recognition")
    }
}
