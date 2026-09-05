import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// A ``WordCorrecting`` that proposes whatever the test scripts, and can be caught in the act.
private final class FakeCorrector: WordCorrecting, Sendable {
    private struct State: Sendable {
        var seen: [Transcription] = []
        var contexts: [AppContext] = []
    }

    private let proposals: [DictationCorrection]
    private let refuses: Bool
    private let state = Mutex(State())

    init(proposing proposals: [DictationCorrection] = [], refuses: Bool = false) {
        self.proposals = proposals
        self.refuses = refuses
    }

    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> [DictationCorrection] {
        state.withLock {
            $0.seen.append(transcription)
            $0.contexts.append(context)
        }
        guard !refuses else { throw .storeRefused }
        return proposals
    }

    var seen: [Transcription] { state.withLock { $0.seen } }
    var contexts: [AppContext] { state.withLock { $0.contexts } }
}

/// A ``SnippetExpanding`` that replaces one phrase, or refuses.
private final class FakeExpander: SnippetExpanding, Sendable {
    private let answer: @Sendable (String) -> ExpandedTranscript
    private let refuses: Bool
    private let state = Mutex<[String]>([])

    init(
        refuses: Bool = false,
        answering answer: @escaping @Sendable (String) -> ExpandedTranscript = {
            ExpandedTranscript.unchanged($0)
        }
    ) {
        self.refuses = refuses
        self.answer = answer
    }

    func expand(_ text: String) async throws(DictationChangeError) -> ExpandedTranscript {
        state.withLock { $0.append(text) }
        guard !refuses else { throw .storeRefused }
        return answer(text)
    }

    var seen: [String] { state.withLock { $0 } }
}

/// A ``DictationLearning`` that remembers what it is told, and can refuse.
private final class FakeLearner: DictationLearning, Sendable {
    private struct State: Sendable {
        var entries: [UUID] = []
        var snippets: [[UUID]] = []
    }

    private let refuses: Bool
    private let state = Mutex(State())

    init(refuses: Bool = false) {
        self.refuses = refuses
    }

    func recordUse(ofEntry id: UUID) async throws(DictationChangeError) {
        state.withLock { $0.entries.append(id) }
        guard !refuses else { throw .storeRefused }
    }

    func recordUse(ofSnippets ids: [UUID]) async throws(DictationChangeError) {
        state.withLock { $0.snippets.append(ids) }
        guard !refuses else { throw .storeRefused }
    }

    var entries: [UUID] { state.withLock { $0.entries } }
    var snippets: [[UUID]] { state.withLock { $0.snippets } }
}

/// A ``VocabularyLearning`` that remembers everything it is offered, and can refuse.
private final class FakeVocabulary: VocabularyLearning, Sendable {
    /// One lesson: what was said, what was written, and what was on screen.
    struct Lesson: Sendable, Equatable {
        let heard: String
        let wrote: String
        let context: AppContext
    }

    private let refuses: Bool
    private let state = Mutex<[Lesson]>([])

    init(refuses: Bool = false) {
        self.refuses = refuses
    }

    func learn(
        heard: String, wrote: String, seeing context: AppContext
    ) async throws(DictationChangeError) {
        state.withLock { $0.append(Lesson(heard: heard, wrote: wrote, context: context)) }
        guard !refuses else { throw .storeRefused }
    }

    var lessons: [Lesson] { state.withLock { $0 } }
}

/// A ``TranscriptCleaning`` that records what it is asked to tidy.
private final class FakeCleaner: TranscriptCleaning, Sendable {
    private let state = Mutex<[TransformationRequest]>([])
    private let tidy: @Sendable (String) -> String

    init(tidying tidy: @escaping @Sendable (String) -> String = { $0 }) {
        self.tidy = tidy
    }

    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        state.withLock { $0.append(request) }
        return TransformationResult(
            text: tidy(request.transcription.text), producedBy: .foundationModels)
    }

    var requests: [TransformationRequest] { state.withLock { $0 } }
}

/// A ``TextInserting`` that records every string it is handed.
private final class FakeInserter: TextInserting, Sendable {
    private let state = Mutex<[String]>([])
    private let refuses: Bool

    init(refuses: Bool = false) {
        self.refuses = refuses
    }

    func insert(_ text: String) async throws(TextInsertionError) -> TextInsertionMethod {
        state.withLock { $0.append(text) }
        guard !refuses else { throw .clipboardUnavailable }
        return .accessibility
    }

    var received: [String] { state.withLock { $0 } }
}

// MARK: - Fixtures

private let heard = "open the payment sheet and send my address"
private let entry = UUID()
private let snippet = UUID()

private let paymentSheet = DictationCorrection(
    heard: "payment sheet", wrote: "PaymentSheet", wordRange: 2..<4, entryID: entry,
    reason: "heardAsSeveralWords", heardConfidence: 0.2)

private func makePipeline(
    spoken: String = heard,
    cleaner: FakeCleaner = FakeCleaner(),
    inserter: FakeInserter = FakeInserter(),
    corrector: any WordCorrecting = NoTextChanges(),
    snippets: any SnippetExpanding = NoTextChanges(),
    learner: any DictationLearning = NoTextChanges(),
    vocabulary: any VocabularyLearning = NoTextChanges(),
    context: FakeContextEngine = FakeContextEngine(context: .fixture())
) -> DictationPipeline {
    DictationPipeline(
        capture: FakeAudioCaptureEngine(),
        speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: spoken))),
        cleaner: cleaner,
        context: context,
        inserter: inserter,
        corrector: corrector,
        snippets: snippets,
        learner: learner,
        vocabulary: vocabulary,
        metrics: RecordingMetricsRecorder(),
        clock: ManualClock()
    )
}

/// One whole dictation, start to finish.
private func dictate(with pipeline: DictationPipeline) async {
    await pipeline.startRecording()
    await pipeline.finishRecording()
}

extension DictationPipeline {
    /// The finished dictation, or `nil` if this one did not finish.
    fileprivate var outcome: DictationOutcome? {
        guard case .inserted(let outcome) = currentState else { return nil }
        return outcome
    }
}

// MARK: - Tests

@Suite("Dictation pipeline: the user's own words")
struct DictationPipelineCorrectionTests {
    /// A correction is argued from the sentence as heard, and the tidier's job is to rewrite it.
    @Test("Corrects the transcript before the tidier sees it")
    func correctsBeforeTidying() async {
        let cleaner = FakeCleaner()
        let pipeline = makePipeline(
            cleaner: cleaner, corrector: FakeCorrector(proposing: [paymentSheet]))

        await dictate(with: pipeline)

        #expect(
            cleaner.requests.map(\.transcription.text)
                == ["open the PaymentSheet and send my address"])
    }

    @Test("Carries every change out with the finished dictation")
    func carriesTheChangesOut() async {
        let pipeline = makePipeline(corrector: FakeCorrector(proposing: [paymentSheet]))

        await dictate(with: pipeline)

        let changes = await pipeline.outcome?.changes
        #expect(changes?.corrections.map(\.wrote) == ["PaymentSheet"])
        #expect(changes?.corrections.first?.heard == "payment sheet")
        #expect(changes?.corrections.first?.entryID == entry)
    }

    /// §19. A dictionary that will not answer costs a correction, never a dictation.
    @Test("A dictionary that refuses costs the correction and not the words")
    func aRefusedDictionaryCostsNothing() async {
        let inserter = FakeInserter()
        let pipeline = makePipeline(
            inserter: inserter, corrector: FakeCorrector(refuses: true))

        await dictate(with: pipeline)

        #expect(inserter.received == [heard])
        #expect(await pipeline.outcome?.changes.isEmpty == true)
    }

    @Test("Leaves the transcript untouched when nothing is proposed")
    func proposesNothing() async {
        let inserter = FakeInserter()
        let pipeline = makePipeline(inserter: inserter, corrector: FakeCorrector())

        await dictate(with: pipeline)

        #expect(inserter.received == [heard])
        #expect(await pipeline.outcome?.changes == AppliedChanges(spokenWords: 8))
    }

    /// Cancelling leaves no trace, for every stage after transcription too.
    @Test("A cancel arriving during correction stops the dictation dead")
    func cancelDuringCorrection() async {
        let inserter = FakeInserter()
        let trigger = CancelsTheDictation()
        let pipeline = makePipeline(
            inserter: inserter, corrector: CancelsWhileCorrecting(trigger: trigger))
        trigger.aim(at: pipeline)

        await dictate(with: pipeline)

        #expect(inserter.received.isEmpty)
        #expect(await pipeline.currentState == .idle)
    }
}

@Suite("Dictation pipeline: the user's own snippets")
struct DictationPipelineSnippetTests {
    /// The matcher tolerates the tidier's punctuation but refuses a trigger assembled across a full stop.
    @Test("Expands the tidied text, not the raw transcript")
    func expandsAfterTidying() async {
        let expander = FakeExpander()
        let pipeline = makePipeline(
            cleaner: FakeCleaner(tidying: { $0.capitalisedFirst + "." }), snippets: expander)

        await dictate(with: pipeline)

        #expect(expander.seen == ["Open the payment sheet and send my address."])
    }

    @Test("Inserts the expansion, and says which snippets fired")
    func insertsTheExpansion() async {
        let inserter = FakeInserter()
        let pipeline = makePipeline(
            inserter: inserter,
            snippets: FakeExpander(answering: { _ in
                ExpandedTranscript(
                    text: "open the payment sheet and send 12 Some Street",
                    snippets: [
                        SnippetUse(
                            snippetID: snippet, matched: "my address",
                            expansion: "12 Some Street")
                    ])
            }))

        await dictate(with: pipeline)

        #expect(inserter.received == ["open the payment sheet and send 12 Some Street"])
        #expect(await pipeline.outcome?.changes.snippets.map(\.snippetID) == [snippet])
    }

    /// §19 again, and the same rule the tidier is held to.
    @Test("A snippet store that refuses costs the expansion and not the words")
    func aRefusedStoreCostsNothing() async {
        let inserter = FakeInserter()
        let pipeline = makePipeline(inserter: inserter, snippets: FakeExpander(refuses: true))

        await dictate(with: pipeline)

        #expect(inserter.received == [heard])
    }

    /// The Accessibility route replaces the selection, so an empty insertion would delete it.
    @Test("An expansion that comes back blank is refused, not inserted")
    func aBlankExpansionIsRefused() async {
        let inserter = FakeInserter()
        let pipeline = makePipeline(
            inserter: inserter, snippets: FakeExpander(answering: { _ in .unchanged("   ") }))

        await dictate(with: pipeline)

        #expect(inserter.received == [heard])
        #expect(await pipeline.outcome?.changes.snippets.isEmpty == true)
    }

    @Test("A cancel arriving during expansion stops the dictation dead")
    func cancelDuringExpansion() async {
        let inserter = FakeInserter()
        let trigger = CancelsTheDictation()
        let pipeline = makePipeline(
            inserter: inserter, snippets: CancelsWhileExpanding(trigger: trigger))
        trigger.aim(at: pipeline)

        await dictate(with: pipeline)

        #expect(inserter.received.isEmpty)
        #expect(await pipeline.currentState == .idle)
    }
}

@Suite("Dictation pipeline: what it learns")
struct DictationPipelineLearningTests {
    @Test("Counts the entry behind every correction that survived")
    func countsTheEntries() async {
        let learner = FakeLearner()
        let pipeline = makePipeline(
            corrector: FakeCorrector(proposing: [paymentSheet]), learner: learner)

        await dictate(with: pipeline)

        #expect(learner.entries == [entry])
    }

    /// The dictionary counts dictations an entry applied to, not words.
    @Test("Counts one entry once, however many words it corrected")
    func countsAnEntryOnce() async {
        let learner = FakeLearner()
        let twice = [
            paymentSheet,
            DictationCorrection(
                heard: "my address", wrote: "PaymentSheet", wordRange: 6..<8, entryID: entry,
                reason: "heardAsSeveralWords", heardConfidence: 0.2),
        ]
        let pipeline = makePipeline(corrector: FakeCorrector(proposing: twice), learner: learner)

        await dictate(with: pipeline)

        #expect(learner.entries == [entry])
    }

    /// The snippet store counts firings rather than dictations, and says so.
    @Test("Counts a snippet that fired twice, twice")
    func countsEveryFiring() async {
        let learner = FakeLearner()
        let pipeline = makePipeline(
            snippets: FakeExpander(answering: { _ in
                ExpandedTranscript(
                    text: "here and here",
                    snippets: [
                        SnippetUse(snippetID: snippet, matched: "here", expansion: "here"),
                        SnippetUse(snippetID: snippet, matched: "here", expansion: "here"),
                    ])
            }),
            learner: learner)

        await dictate(with: pipeline)

        #expect(learner.snippets == [[snippet, snippet]])
    }

    /// The guard that makes this free for a user with neither a dictionary nor a snippet.
    @Test("Says nothing to either store when nothing changed")
    func learnsNothingFromAnUnchangedDictation() async {
        let learner = FakeLearner()
        let pipeline = makePipeline(learner: learner)

        await dictate(with: pipeline)

        #expect(learner.entries.isEmpty)
        #expect(learner.snippets.isEmpty)
    }

    /// A word earns its place by surviving a dictation; one that never landed proves nothing.
    @Test("Learns nothing from a dictation that never landed")
    func learnsNothingFromAFailedInsertion() async {
        let learner = FakeLearner()
        let pipeline = makePipeline(
            inserter: FakeInserter(refuses: true),
            corrector: FakeCorrector(proposing: [paymentSheet]), learner: learner)

        await dictate(with: pipeline)

        #expect(learner.entries.isEmpty)
    }

    /// This runs after the dictation is announced as inserted, so a refused note cannot be a failure.
    @Test("A store that refuses the note does not undo the dictation")
    func aRefusedNoteChangesNothing() async {
        let inserter = FakeInserter()
        let pipeline = makePipeline(
            inserter: inserter, corrector: FakeCorrector(proposing: [paymentSheet]),
            snippets: FakeExpander(answering: { text in
                ExpandedTranscript(
                    text: text,
                    snippets: [SnippetUse(snippetID: snippet, matched: "x", expansion: "x")])
            }),
            learner: FakeLearner(refuses: true))

        await dictate(with: pipeline)

        #expect(await pipeline.outcome?.text == "open the PaymentSheet and send my address")
        #expect(inserter.received.count == 1)
    }
}

@Suite("Dictation pipeline: growing the user's vocabulary")
struct DictationPipelineVocabularyTests {
    /// Three different things: the raw transcript, the text that landed, and the one screen reading.
    @Test("Offers the dictionary what was said, what was written and what was on screen")
    func offersTheWholeDictation() async {
        let vocabulary = FakeVocabulary()
        let pipeline = makePipeline(
            cleaner: FakeCleaner(tidying: \.capitalisedFirst), vocabulary: vocabulary)

        await dictate(with: pipeline)

        #expect(
            vocabulary.lessons == [
                FakeVocabulary.Lesson(
                    heard: heard, wrote: heard.capitalisedFirst, context: .fixture())
            ])
    }

    /// The question this path asks is what the user *said*, before anything rewrote it.
    @Test("Offers what the recogniser heard, not what the dictionary already changed")
    func offersTheRawTranscript() async {
        let vocabulary = FakeVocabulary()
        let pipeline = makePipeline(
            corrector: FakeCorrector(proposing: [paymentSheet]), vocabulary: vocabulary)

        await dictate(with: pipeline)

        #expect(vocabulary.lessons.map(\.heard) == [heard])
        #expect(vocabulary.lessons.map(\.wrote) == ["open the PaymentSheet and send my address"])
    }

    /// A word earns its place by surviving a dictation; one that never landed showed nobody anything.
    @Test("Teaches the dictionary nothing when the words never landed")
    func learnsNothingFromAFailedInsertion() async {
        let vocabulary = FakeVocabulary()
        let pipeline = makePipeline(
            inserter: FakeInserter(refuses: true), vocabulary: vocabulary)

        await dictate(with: pipeline)

        #expect(vocabulary.lessons.isEmpty)
    }

    /// Both learning paths read the screen, so with no screen there is no raw material.
    @Test("Does not cross the seam when macOS said nothing about the screen")
    func learnsNothingWithoutAScreen() async {
        let vocabulary = FakeVocabulary()
        let pipeline = makePipeline(
            vocabulary: vocabulary, context: FakeContextEngine(context: .unknown))

        await dictate(with: pipeline)

        #expect(vocabulary.lessons.isEmpty)
    }

    /// §19: a store that will not take the lesson costs the lesson and nothing else.
    @Test("A dictionary that refuses the lesson does not spoil the dictation")
    func aRefusedLessonChangesNothing() async {
        let inserter = FakeInserter()
        let pipeline = makePipeline(
            inserter: inserter, vocabulary: FakeVocabulary(refuses: true))

        await dictate(with: pipeline)

        #expect(inserter.received == [heard])
        #expect(await pipeline.outcome?.text == heard)
    }

    /// A word learnt from an abandoned dictation would be a trace that outlived it.
    @Test("A cancelled dictation teaches nothing")
    func aCancelledDictationTeachesNothing() async {
        let vocabulary = FakeVocabulary()
        let trigger = CancelsTheDictation()
        let pipeline = makePipeline(
            snippets: CancelsWhileExpanding(trigger: trigger), vocabulary: vocabulary)
        trigger.aim(at: pipeline)

        await dictate(with: pipeline)

        #expect(vocabulary.lessons.isEmpty)
    }
}

@Suite("Dictation pipeline: what it reads off the screen")
struct DictationPipelineContextTests {
    /// One Accessibility round trip per dictation; two could describe two different screens.
    @Test("Reads the screen once and shows the same reading to everything")
    func readsTheScreenOnce() async {
        let context = FakeContextEngine(context: .fixture())
        let cleaner = FakeCleaner()
        let corrector = FakeCorrector()
        let pipeline = makePipeline(cleaner: cleaner, corrector: corrector, context: context)

        await dictate(with: pipeline)

        #expect(await context.calls.count == 1)
        #expect(corrector.contexts == [.fixture()])
        #expect(cleaner.requests.map(\.context) == [.fixture()])
    }

    @Test("Still names the application the words went into")
    func namesTheApplication() async {
        let pipeline = makePipeline(corrector: FakeCorrector(proposing: [paymentSheet]))

        await dictate(with: pipeline)

        #expect(await pipeline.outcome?.insertedInto == "Slack")
    }
}

// MARK: - Staging a cancel from inside a stage

/// A stage that abandons the dictation it is in; aimed at its pipeline after both exist.
private final class CancelsTheDictation: Sendable {
    private let target = Mutex<DictationPipeline?>(nil)

    func aim(at pipeline: DictationPipeline) { target.withLock { $0 = pipeline } }

    func fire() async { await target.withLock { $0 }?.cancel() }
}

private struct CancelsWhileCorrecting: WordCorrecting {
    let trigger: CancelsTheDictation

    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async -> [DictationCorrection] {
        await trigger.fire()
        return []
    }
}

private struct CancelsWhileExpanding: SnippetExpanding {
    let trigger: CancelsTheDictation

    func expand(_ text: String) async -> ExpandedTranscript {
        await trigger.fire()
        return .unchanged(text)
    }
}

extension String {
    /// The same sentence with a capital at the front, the visible part of tidying.
    fileprivate var capitalisedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
