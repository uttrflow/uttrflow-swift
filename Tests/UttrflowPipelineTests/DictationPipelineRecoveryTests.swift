import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// A ``TranscriptCleaning`` that can be scripted to tidy or to fail, and that records
/// every request it was handed.
///
/// Named for this file so it can sit alongside the other pipeline test files' own
/// cleaners in one test target.
private final class RecoveryFakeCleaner: TranscriptCleaning, Sendable {
    private struct State: Sendable {
        var outcome: ScriptedOutcome<TransformationResult, TransformationError>
        var requests: [TransformationRequest] = []
    }

    private let state: Mutex<State>
    private let clock: ManualClock?
    private let takes: Duration

    init(
        outcome: ScriptedOutcome<TransformationResult, TransformationError> = .success(
            TransformationResult(text: "Tidied text.", producedBy: .foundationModels)),
        clock: ManualClock? = nil,
        takes: Duration = .zero
    ) {
        self.state = Mutex(State(outcome: outcome))
        self.clock = clock
        self.takes = takes
    }

    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        let outcome = state.withLock { state -> ScriptedOutcome<TransformationResult, TransformationError> in
            state.requests.append(request)
            return state.outcome
        }
        clock?.advance(by: takes)
        return try outcome.resolve()
    }

    /// Every request the pipeline sent, in order.
    var requests: [TransformationRequest] { state.withLock { $0.requests } }
}

/// A ``TextInserting`` that can be scripted to place text or to fail, and that records
/// exactly what it was asked to insert.
private final class RecoveryFakeInserter: TextInserting, Sendable {
    private struct State: Sendable {
        var outcome: ScriptedOutcome<TextInsertionMethod, TextInsertionError>
        var received: [String] = []
    }

    private let state: Mutex<State>
    private let clock: ManualClock?
    private let takes: Duration

    init(
        outcome: ScriptedOutcome<TextInsertionMethod, TextInsertionError> = .success(.accessibility),
        clock: ManualClock? = nil,
        takes: Duration = .zero
    ) {
        self.state = Mutex(State(outcome: outcome))
        self.clock = clock
        self.takes = takes
    }

    func insert(_ text: String) async throws(TextInsertionError) -> TextInsertionMethod {
        let outcome = state.withLock { state -> ScriptedOutcome<TextInsertionMethod, TextInsertionError> in
            state.received.append(text)
            return state.outcome
        }
        clock?.advance(by: takes)
        return try outcome.resolve()
    }

    /// Every string the pipeline asked to have inserted, in order.
    var received: [String] { state.withLock { $0.received } }
}

/// A ``WordCorrecting`` that costs the dictation time and, by default, proposes nothing
/// — which is what a dictionary does on almost every dictation.
private struct RecoveryFakeCorrector: WordCorrecting {
    var proposals: [DictationCorrection] = []
    var refuses = false
    var clock: ManualClock?
    var takes: Duration = .zero

    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> [DictationCorrection] {
        clock?.advance(by: takes)
        guard !refuses else { throw .storeRefused }
        return proposals
    }
}

/// A ``SnippetExpanding`` that costs the dictation time and, by default, matches nothing.
private struct RecoveryFakeExpander: SnippetExpanding {
    var replacing: (from: String, to: String)?
    var refuses = false
    var clock: ManualClock?
    var takes: Duration = .zero

    func expand(_ text: String) async throws(DictationChangeError) -> ExpandedTranscript {
        clock?.advance(by: takes)
        guard !refuses else { throw .storeRefused }
        guard let replacing, text.contains(replacing.from) else { return .unchanged(text) }
        return ExpandedTranscript(
            text: text.replacingOccurrences(of: replacing.from, with: replacing.to),
            snippets: [
                SnippetUse(snippetID: UUID(), matched: replacing.from, expansion: replacing.to)
            ])
    }
}

/// An error from outside the product's own vocabulary, for the fallback path.
private struct OddError: Error {}

/// A short, realistic raw transcript: filler word, no punctuation, lowercase.
private let spokenWords = "um i'll be about twenty minutes late to the meeting"
/// What a working transformer would make of it.
private let tidiedWords = "I'll be about twenty minutes late to the meeting."

// MARK: - Reading the end state

extension DictationState {
    fileprivate var insertedOutcome: DictationOutcome? {
        if case .inserted(let outcome) = self { outcome } else { nil }
    }

    fileprivate var failure: DictationFailure? {
        if case .failed(let failure) = self { failure } else { nil }
    }
}

// MARK: - Tests

@Suite("Dictation pipeline: the user's words survive")
struct DictationPipelineRecoveryTests {
    private func makePipeline(
        speech: FakeSpeechEngine = FakeSpeechEngine(
            transcribeOutcome: .success(.fixture(text: spokenWords))),
        cleaner: RecoveryFakeCleaner = RecoveryFakeCleaner(
            outcome: .success(
                TransformationResult(text: tidiedWords, producedBy: .foundationModels))),
        context: FakeContextEngine = FakeContextEngine(context: .fixture()),
        inserter: RecoveryFakeInserter = RecoveryFakeInserter(),
        corrector: any WordCorrecting = NoTextChanges(),
        snippets: any SnippetExpanding = NoTextChanges(),
        metrics: any MetricsRecording = NoOpMetricsRecorder(),
        clock: any Clock<Duration> = ContinuousClock(),
        profile: UserProfile = .default
    ) -> DictationPipeline {
        DictationPipeline(
            capture: FakeAudioCaptureEngine(),
            speech: speech,
            cleaner: cleaner,
            context: context,
            inserter: inserter,
            corrector: corrector,
            snippets: snippets,
            metrics: metrics,
            clock: clock,
            profile: profile
        )
    }

    /// Speak, stop, and let the pipeline run to whatever end it reaches.
    private func dictate(_ pipeline: DictationPipeline) async -> DictationState {
        await pipeline.startRecording()
        await pipeline.finishRecording()
        return await pipeline.currentState
    }

    /// Tidying is a nicety; the words are the product. If a failed clean-up could sink a
    /// dictation, the user would speak a paragraph and be handed nothing — the one
    /// failure mode this pipeline exists to prevent.
    @Test("when tidying fails the pipeline inserts exactly what the user actually said")
    func tidyingFailureInsertsTheRawTranscript() async throws {
        let inserter = RecoveryFakeInserter()
        let pipeline = makePipeline(
            cleaner: RecoveryFakeCleaner(outcome: .failure(.noCapableTransformer)),
            inserter: inserter
        )

        let state = await dictate(pipeline)

        let outcome = try #require(
            state.insertedOutcome, "a failed tidy-up must not cost the user their words")
        #expect(outcome.text == spokenWords)
        #expect(inserter.received == [spokenWords])
        #expect(state.failure == nil)
    }

    /// The record of what tidied a transcript feeds evaluation. Crediting an engine that
    /// threw would quietly flatter it and hide the regression.
    @Test("a transcript that could not be tidied is attributed to the rules, not the engine that failed")
    func tidyingFailureIsAttributedToTheRules() async throws {
        let pipeline = makePipeline(
            cleaner: RecoveryFakeCleaner(
                outcome: .failure(.transformFailed(kind: .foundationModels, description: "model died")))
        )

        let state = await dictate(pipeline)

        let outcome = try #require(state.insertedOutcome)
        #expect(outcome.cleanedBy == .rules)
    }

    /// Insertion is the last thing that can go wrong, and the point at which the words
    /// exist nowhere else. Carrying the transcript out with the failure is what lets the
    /// interface offer them rather than lose them.
    @Test("when insertion fails the failure still carries the words so they can be offered")
    func insertionFailureCarriesTheTranscript() async throws {
        let pipeline = makePipeline(
            inserter: RecoveryFakeInserter(outcome: .failure(.noFocusedTextField)))

        let state = await dictate(pipeline)

        let failure = try #require(
            state.failure, "a failed insertion must be reported, not swallowed")
        let transcript = try #require(
            failure.transcript, "losing the words at the final step is the worst outcome of all")
        #expect(transcript == tidiedWords)
    }

    @Test("when tidying succeeds it is the cleaned text that is inserted, not the raw one")
    func tidiedTextIsPreferredWhenAvailable() async throws {
        let inserter = RecoveryFakeInserter()
        let pipeline = makePipeline(inserter: inserter)

        let state = await dictate(pipeline)

        let outcome = try #require(state.insertedOutcome)
        #expect(outcome.text == tidiedWords)
        #expect(outcome.cleanedBy == .foundationModels)
        #expect(inserter.received == [tidiedWords])
    }

    /// The only honest empty-handed ending: transcription failing means there were never
    /// any words to keep, so there is nothing to offer and nothing to insert.
    @Test("when transcription fails the dictation ends with no transcript and nothing inserted")
    func transcriptionFailureHasNothingToSalvage() async throws {
        let inserter = RecoveryFakeInserter()
        let cleaner = RecoveryFakeCleaner()
        let pipeline = makePipeline(
            speech: FakeSpeechEngine(transcribeOutcome: .failure(.transcriptionFailed(description: "x"))),
            cleaner: cleaner,
            inserter: inserter
        )

        let state = await dictate(pipeline)

        let failure = try #require(state.failure)
        #expect(failure.transcript == nil)
        #expect(inserter.received.isEmpty)
        #expect(cleaner.requests.isEmpty)
    }

    @Test("a failure shows the sentence and the recovery the underlying error itself defines")
    func failureTextComesFromTheUnderlyingError() async throws {
        let speechError = SpeechEngineError.modelNotInstalled
        let speechState = await dictate(
            makePipeline(speech: FakeSpeechEngine(transcribeOutcome: .failure(speechError))))
        let speechFailure = try #require(speechState.failure)
        #expect(speechFailure.message == speechError.userMessage)
        #expect(speechFailure.recovery == speechError.recovery)

        let insertionError = TextInsertionError.accessibilityDenied
        let insertionState = await dictate(
            makePipeline(inserter: RecoveryFakeInserter(outcome: .failure(insertionError))))
        let insertionFailure = try #require(insertionState.failure)
        #expect(insertionFailure.message == insertionError.userMessage)
        #expect(insertionFailure.recovery == insertionError.recovery)
        #expect(insertionFailure.recovery == .openSystemSettings(.accessibility))
    }

    /// An unforeseen error must still reach the user as a sentence. A leaked type name
    /// is not something anyone can act on.
    @Test("an error the product does not know falls back to a plain sentence with no type name in it")
    func unknownErrorsGetAPlainSentence() {
        let failure = DictationFailure(OddError(), transcript: spokenWords)

        #expect(failure.message == "Something went wrong. Please try again.")
        #expect(failure.recovery == .retry)
        #expect(!failure.message.contains("OddError"))
        #expect(!failure.message.contains("Error"))
        #expect(failure.transcript == spokenWords, "even an unknown failure keeps the words")
    }

    @Test("a successful dictation records every stage of the journey, in order, as succeeded")
    func successfulRunMeasuresEveryStage() async {
        let recorder = RecordingMetricsRecorder()
        let clock = ManualClock()
        let pipeline = makePipeline(
            cleaner: RecoveryFakeCleaner(
                outcome: .success(TransformationResult(text: tidiedWords, producedBy: .foundationModels)),
                clock: clock,
                takes: .milliseconds(120)),
            inserter: RecoveryFakeInserter(clock: clock, takes: .milliseconds(30)),
            corrector: RecoveryFakeCorrector(clock: clock, takes: .milliseconds(4)),
            snippets: RecoveryFakeExpander(clock: clock, takes: .milliseconds(2)),
            metrics: recorder,
            clock: clock
        )

        _ = await dictate(pipeline)

        let measurements = await recorder.measurements
        // Capture is here because draining and converting the buffer is a cost Uttrflow
        // imposes. The wait before it — the user holding the key — is not a stage, and
        // is reported separately as the outcome's `spokenFor`.
        #expect(
            measurements.map(\.stage) == [
                .capture, .transcription, .correction, .transformation, .expansion, .insertion,
            ])
        #expect(measurements.allSatisfy { $0.succeeded })
        #expect(
            measurements.map(\.duration) == [
                .zero, .zero, .milliseconds(4), .milliseconds(120), .milliseconds(2),
                .milliseconds(30),
            ])
    }

    /// The whole point of measuring these two. A dictionary that matched no word and a
    /// snippet file no trigger fired in were both still read, and the dictation waited
    /// for both — so a fast path that hides them reports a journey nobody took.
    @Test("the dictionary and the snippets are timed even when they change nothing")
    func stagesThatChangeNothingAreStillTimed() async {
        let recorder = RecordingMetricsRecorder()
        let clock = ManualClock()
        let pipeline = makePipeline(
            corrector: RecoveryFakeCorrector(clock: clock, takes: .milliseconds(6)),
            snippets: RecoveryFakeExpander(clock: clock, takes: .milliseconds(3)),
            metrics: recorder,
            clock: clock
        )

        let state = await dictate(pipeline)

        #expect(state.insertedOutcome?.changes.isEmpty == true, "nothing was changed")
        #expect(await recorder.measurements(for: .correction).map(\.duration) == [.milliseconds(6)])
        #expect(await recorder.measurements(for: .expansion).map(\.duration) == [.milliseconds(3)])
    }

    /// A store that will not answer is the stage failing, not the dictation failing, and
    /// the reliability figures have to be able to tell those apart.
    @Test("a dictionary or a snippet store that refuses is recorded as a failed stage")
    func refusingStoresAreRecordedAsFailures() async {
        let recorder = RecordingMetricsRecorder()
        let clock = ManualClock()
        let pipeline = makePipeline(
            corrector: RecoveryFakeCorrector(refuses: true, clock: clock, takes: .milliseconds(5)),
            snippets: RecoveryFakeExpander(refuses: true, clock: clock, takes: .milliseconds(1)),
            metrics: recorder,
            clock: clock
        )

        let state = await dictate(pipeline)

        #expect(state.insertedOutcome != nil, "the words still go in")
        let correction = await recorder.measurements(for: .correction)
        #expect(correction.map(\.succeeded) == [false])
        #expect(correction.map(\.duration) == [.milliseconds(5)])
        let expansion = await recorder.measurements(for: .expansion)
        #expect(expansion.map(\.succeeded) == [false])
        #expect(expansion.map(\.duration) == [.milliseconds(1)])
    }

    /// Everything above drives a clock the test owns, which proves the wiring but not
    /// that the wiring survives real time. This one runs the whole pipeline against the
    /// real clock, with a dictionary that corrects a word and a snippet that fires, and
    /// insists that all six stages come back with a duration that was actually spent.
    @Test("a real dictation, on the real clock, times all six stages")
    func realDictationTimesEveryStage() async {
        let recorder = RecordingMetricsRecorder()
        let pipeline = makePipeline(
            speech: FakeSpeechEngine(
                transcribeOutcome: .success(.fixture(text: "email me the payment sheet kr"))),
            cleaner: RecoveryFakeCleaner(
                outcome: .success(
                    TransformationResult(
                        text: "Email me the PaymentSheet kr.", producedBy: .foundationModels))),
            corrector: RecoveryFakeCorrector(proposals: [
                DictationCorrection(
                    heard: "payment sheet", wrote: "PaymentSheet", wordRange: 3..<5,
                    entryID: UUID(), reason: "heardAsSeveralWords", heardConfidence: 0.3)
            ]),
            snippets: RecoveryFakeExpander(replacing: ("kr", "Kind regards, Naveen")),
            metrics: recorder
        )

        let state = await dictate(pipeline)

        #expect(state.insertedOutcome?.text == "Email me the PaymentSheet Kind regards, Naveen.")
        let measurements = await recorder.measurements
        #expect(measurements.map(\.stage) == PipelineStage.allCases)
        #expect(
            measurements.allSatisfy { $0.succeeded && $0.duration > .zero },
            "every stage spent real time and none of it is missing")
    }

    /// The duration the user cares about is how long they talked, and it is the one
    /// thing about a dictation that cannot be recovered after the fact. It is carried
    /// out of the pipeline rather than measured as a stage, because a stage is a cost
    /// Uttrflow imposes: counting the speaker's own pauses as latency would make a
    /// leisurely sentence look like a slow app.
    @Test("the finished dictation says how long the speaker actually talked")
    func spokenDurationIsMeasured() async {
        let clock = ManualClock()
        let pipeline = makePipeline(clock: clock)

        await pipeline.startRecording()
        clock.advance(by: .seconds(11))
        await pipeline.finishRecording()

        guard case .inserted(let outcome) = await pipeline.currentState else {
            Issue.record("expected the dictation to finish")
            return
        }
        #expect(outcome.spokenFor == .seconds(11))
    }

    /// A cancelled attempt must not lend its stopwatch to the next dictation — eleven
    /// seconds of abandoned speech showing up against a two-second one would be wrong
    /// in the history and wrong in any figure derived from it.
    @Test("an abandoned dictation does not lend its duration to the next one")
    func spokenDurationDoesNotLeakAcrossDictations() async {
        let clock = ManualClock()
        let pipeline = makePipeline(clock: clock)

        await pipeline.startRecording()
        clock.advance(by: .seconds(11))
        await pipeline.cancel()

        await pipeline.startRecording()
        clock.advance(by: .seconds(2))
        await pipeline.finishRecording()

        guard case .inserted(let outcome) = await pipeline.currentState else {
            Issue.record("expected the second dictation to finish")
            return
        }
        #expect(outcome.spokenFor == .seconds(2))
    }

    @Test("a stage that fails is recorded as a failure while the stages around it still succeed")
    func failingStagesAreRecordedAsFailures() async {
        let recorder = RecordingMetricsRecorder()
        let clock = ManualClock()
        let pipeline = makePipeline(
            cleaner: RecoveryFakeCleaner(
                outcome: .failure(.outputRejected(reason: "meaning changed")),
                clock: clock,
                takes: .milliseconds(75)),
            inserter: RecoveryFakeInserter(clock: clock, takes: .milliseconds(10)),
            metrics: recorder,
            clock: clock
        )

        _ = await dictate(pipeline)

        let transformation = await recorder.measurements(for: .transformation)
        #expect(transformation.map(\.succeeded) == [false])
        #expect(transformation.map(\.duration) == [.milliseconds(75)])

        let insertion = await recorder.measurements(for: .insertion)
        #expect(
            insertion.map(\.succeeded) == [true],
            "the raw words still go in after tidying fails")
        #expect(insertion.map(\.duration) == [.milliseconds(10)])
    }

    @Test("the context engine is consulted and what it reports reaches the cleaner's request")
    func appContextReachesTheCleaner() async throws {
        let appContext = AppContext.fixture(
            applicationName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            documentName: "DictationPipeline.swift",
            selectedText: "let cleaned"
        )
        let contextEngine = FakeContextEngine(context: appContext)
        let cleaner = RecoveryFakeCleaner()
        let pipeline = makePipeline(cleaner: cleaner, context: contextEngine)

        _ = await dictate(pipeline)

        let contextLookups = await contextEngine.calls.count
        #expect(contextLookups == 1)
        let request = try #require(cleaner.requests.first)
        #expect(request.context == appContext)
        #expect(request.transcription.text == spokenWords)
    }

    @Test("the profile the pipeline was built with reaches the cleaner's request")
    func userProfileReachesTheCleaner() async throws {
        let profile = UserProfile(
            profession: "cardiologist",
            preferredLanguages: [.hindi, .english],
            technicalDomains: ["medicine"],
            preferredWritingStyle: "concise",
            vocabulary: ["echocardiogram"]
        )
        let cleaner = RecoveryFakeCleaner()
        let pipeline = makePipeline(cleaner: cleaner, profile: profile)

        _ = await dictate(pipeline)

        let request = try #require(cleaner.requests.first)
        #expect(request.profile == profile)
    }
}
