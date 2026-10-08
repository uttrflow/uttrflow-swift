// Tests the dictionary, snippet and learning seams inside the pipeline.
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowAI
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

private actor LatePasteSpeech: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private var lines = ["we moved the review", "to the next slot"]

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        Transcription(text: lines.removeFirst(), audioDuration: audio.duration)
    }
}

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
        var entries: [[UUID]] = []
        var texts: [String] = []
        var snippets: [[UUID]] = []
    }

    private let refuses: Bool
    private let state = Mutex(State())

    init(refuses: Bool = false) {
        self.refuses = refuses
    }

    func recordUse(ofEntries ids: [UUID], writtenIn text: String) async throws(DictationChangeError) {
        state.withLock {
            $0.entries.append(ids)
            $0.texts.append(text)
        }
        guard !refuses else { throw .storeRefused }
    }

    func recordUse(ofSnippets ids: [UUID]) async throws(DictationChangeError) {
        state.withLock { $0.snippets.append(ids) }
        guard !refuses else { throw .storeRefused }
    }

    var entries: [[UUID]] { state.withLock { $0.entries } }
    var texts: [String] { state.withLock { $0.texts } }
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

// MARK: - Fixtures

private let heard = "open the payment sheet and send my address"
private let entry = UUID()
private let otherEntry = UUID()
private let snippet = UUID()

private let paymentSheet = DictationCorrection(
    heard: "payment sheet", wrote: "PaymentSheet", wordRange: 2..<4, entryID: entry,
    reason: .heardAsSeveralWords, heardConfidence: 0.2)

private func makePipeline(
    spoken: String = heard,
    cleaner: any TranscriptCleaning = FakeTranscriptCleaner(producedBy: .foundationModels),
    inserter: FakeTextInserter = FakeTextInserter(),
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

private actor LatePasteContext: ContextEngine {
    private var context = AppContext.fixture(precedingText: "")
    private var held: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private var holding = false
    private(set) var reads = 0
    let secondReadBegan = Signal()

    func currentContext() async -> AppContext {
        reads += 1
        if holding, !released {
            await withCheckedContinuation {
                held.append($0)
                secondReadBegan.fire()
            }
        }
        return context
    }

    /// Holds every read from here on until the first paste lands.
    func holdUntilThePasteLands() { holding = true }

    func landFirstPaste() {
        context = .fixture(precedingText: "we moved the review")
        released = true
        for reader in held { reader.resume() }
        held = []
    }
}

private actor LatePasteInserter: TextInserting {
    private(set) var received: [String] = []

    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        received.append(text)
        return InsertionAttempt(.pasteboard, arrival: .unconfirmed)
    }
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
    @Test("the next dictation reads the caret after an unconfirmed paste lands")
    func nextDictationWaitsForThePreviousPaste() async {
        let context = LatePasteContext()
        let inserter = LatePasteInserter()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(),
            speech: LatePasteSpeech(),
            cleaner: FakeTranscriptCleaner(producedBy: .foundationModels), context: context,
            inserter: inserter)

        await pipeline.startRecording()
        await pipeline.finishRecording()
        await context.holdUntilThePasteLands()
        await pipeline.startRecording()
        let second = Task { await pipeline.finishRecording() }
        try? await arrival(of: context.secondReadBegan.fired)
        #expect(await inserter.received == ["we moved the review"])
        await context.landFirstPaste()
        await second.value

        #expect(await inserter.received == ["we moved the review", " to the next slot"])
    }

    /// A correction is argued from the sentence as heard, and the tidier's job is to rewrite it.
    @Test("Corrects the transcript before the tidier sees it")
    func correctsBeforeTidying() async {
        let cleaner = FakeTranscriptCleaner(producedBy: .foundationModels)
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
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(
            inserter: inserter, corrector: FakeCorrector(refuses: true))

        await dictate(with: pipeline)

        #expect(inserter.received == [heard])
        #expect(await pipeline.outcome?.changes.isEmpty == true)
    }

    @Test("Leaves the transcript untouched when nothing is proposed")
    func proposesNothing() async {
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(inserter: inserter, corrector: FakeCorrector())

        await dictate(with: pipeline)

        #expect(inserter.received == [heard])
        #expect(await pipeline.outcome?.changes == AppliedChanges(spokenWords: 8))
    }

    /// Cancelling leaves no trace, for every stage after transcription too.
    @Test("A cancel arriving during correction stops the dictation dead")
    func cancelDuringCorrection() async {
        let inserter = FakeTextInserter()
        let trigger = CancelsTheDictation()
        let pipeline = makePipeline(
            inserter: inserter, corrector: CancelsWhileCorrecting(trigger: trigger))
        trigger.aim(at: pipeline)

        await dictate(with: pipeline)

        #expect(inserter.received.isEmpty)
        #expect(await pipeline.currentState == .idle)
    }
}

@Suite("Dictation pipeline: dictionary terms in restatements")
struct DictationPipelineDictionaryRestatementTests {
    private func correctedPipeline(for spoken: String) -> DictationPipeline {
        makePipeline(
            spoken: spoken,
            cleaner: TransformerRouter(engines: [RuleBasedTransformer()], preference: [.rules]),
            corrector: FakeCorrector(proposing: [
                DictationCorrection(
                    heard: "payment sheet", wrote: "PaymentSheet", wordRange: 5..<7,
                    entryID: entry, reason: .heardAsSeveralWords, heardConfidence: 0.2)
            ]))
    }

    @Test(
        "rules remove every spoken component of a corrected dictionary term",
        arguments: [
            ("push to git hub no wait GitHub", "Push to GitHub"),
            ("open payment sheet scratch that PaymentSheet", "Open PaymentSheet"),
            ("open user profile cache no wait UserProfileCache", "Open UserProfileCache"),
        ]
    )
    func rulesRemoveEverySpokenComponent(spoken: String, expected: String) async {
        let pipeline = makePipeline(
            spoken: spoken,
            cleaner: TransformerRouter(engines: [RuleBasedTransformer()], preference: [.rules]))

        await dictate(with: pipeline)

        let actual = await pipeline.outcome?.text
        #expect(actual == expected, "Actual output: \(actual ?? "<nil>")")
    }

    @Test("removes the old phrase after sorry and keeps the corrected word index")
    func sorryBeforeDictionaryTerm() async {
        let pipeline = correctedPipeline(for: "open the payment form sorry payment sheet")

        await dictate(with: pipeline)

        #expect(await pipeline.outcome?.text == "Open the PaymentSheet")
        #expect(await pipeline.outcome?.changes.corrections.first?.writtenWordIndex == 2)
    }

    @Test("removes the old phrase after i mean and keeps the corrected word index")
    func meanBeforeDictionaryTerm() async {
        let pipeline = correctedPipeline(for: "open payment form I mean payment sheet")

        await dictate(with: pipeline)

        #expect(await pipeline.outcome?.text == "Open PaymentSheet")
        #expect(await pipeline.outcome?.changes.corrections.first?.writtenWordIndex == 1)
    }

    @Test("keeps the control restatement when its heard anchor matches")
    func matchingSpokenAnchorControl() async {
        let pipeline = makePipeline(
            spoken: "open the payment form sorry payment page",
            cleaner: TransformerRouter(engines: [RuleBasedTransformer()], preference: [.rules]))

        await dictate(with: pipeline)

        #expect(await pipeline.outcome?.text == "Open the payment page")
    }
}

@Suite("Dictation pipeline: the user's own snippets")
struct DictationPipelineSnippetTests {
    /// The matcher tolerates the tidier's punctuation but refuses a trigger assembled across a full stop.
    @Test("Expands the tidied text, not the raw transcript")
    func expandsAfterTidying() async {
        let expander = FakeExpander()
        let pipeline = makePipeline(
            cleaner: FakeTranscriptCleaner(
                tidying: { $0.capitalisedFirst + "." }, producedBy: .foundationModels), snippets: expander)

        await dictate(with: pipeline)

        #expect(expander.seen == ["Open the payment sheet and send my address."])
    }

    @Test("Inserts the expansion, and says which snippets fired")
    func insertsTheExpansion() async {
        let inserter = FakeTextInserter()
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

    /// A line break is Return in a single-line field, so it would submit the words half-written.
    @Test("A multi-line expansion goes into a single-line field on one line")
    func flattensAnExpansionForOneLine() async {
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(
            inserter: inserter, snippets: signingExpander(),
            context: FakeContextEngine(
                context: .fixture(
                    applicationName: "Numbers", bundleIdentifier: "com.apple.iWork.Numbers",
                    documentName: "Budget")))

        await dictate(with: pipeline)

        #expect(inserter.received == ["send Regards, Asha"])
        #expect(inserter.received.allSatisfy { !$0.contains(where: \.isNewline) })
        #expect(await pipeline.outcome?.changes.snippets.map(\.expansion) == ["Regards, Asha"])
    }

    @Test("A multi-line expansion keeps its line breaks where the field takes them")
    func keepsAnExpansionsLinesWhereTheyFit() async {
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(inserter: inserter, snippets: signingExpander())

        await dictate(with: pipeline)

        #expect(inserter.received == ["send Regards,\n  Asha"])
    }

    /// An expander that signs off over two lines, the second indented.
    private func signingExpander() -> FakeExpander {
        FakeExpander(answering: { _ in
            ExpandedTranscript(
                text: "send Regards,\n  Asha",
                snippets: [
                    SnippetUse(snippetID: snippet, matched: "my signature", expansion: "Regards,\n  Asha")
                ])
        })
    }

    /// §19 again, and the same rule the tidier is held to.
    @Test("A snippet store that refuses costs the expansion and not the words")
    func aRefusedStoreCostsNothing() async {
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(inserter: inserter, snippets: FakeExpander(refuses: true))

        await dictate(with: pipeline)

        #expect(inserter.received == [heard])
    }

    /// The Accessibility route replaces the selection, so an empty insertion would delete it.
    @Test("An expansion that comes back blank is refused, not inserted")
    func aBlankExpansionIsRefused() async {
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(
            inserter: inserter, snippets: FakeExpander(answering: { _ in .unchanged("   ") }))

        await dictate(with: pipeline)

        #expect(inserter.received == [heard])
        #expect(await pipeline.outcome?.changes.snippets.isEmpty == true)
    }

    @Test("A cancel arriving during expansion stops the dictation dead")
    func cancelDuringExpansion() async {
        let inserter = FakeTextInserter()
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

        #expect(learner.entries == [[entry]])
    }

    /// Issue 219: a spelling that reached the user through the doubtful-word line was never counted, so it could never retire.
    @Test("Counts the entry behind a reading the tidier took, as it counts a correction's")
    func countsAReadingTaken() async {
        let learner = FakeLearner()
        let pipeline = makePipeline(
            cleaner: FakeTranscriptCleaner(producedBy: .foundationModels, taking: [entry]), learner: learner)

        await dictate(with: pipeline)

        #expect(learner.entries == [[entry]])
        #expect(await pipeline.outcome?.changes.entriesTaken == [entry])
    }

    /// Either path applying an entry is one dictation it was applied to, so the store hears of it once.
    @Test("Counts an entry once when a correction and a taken reading both used it")
    func countsAnEntryOnceAcrossBothPaths() async {
        let learner = FakeLearner()
        let pipeline = makePipeline(
            cleaner: FakeTranscriptCleaner(producedBy: .foundationModels, taking: [entry, otherEntry]),
            corrector: FakeCorrector(proposing: [paymentSheet]), learner: learner)

        await dictate(with: pipeline)

        #expect(learner.entries == [[entry, otherEntry]])
    }

    /// The dictionary counts dictations an entry applied to, not words.
    @Test("Counts one entry once, however many words it corrected")
    func countsAnEntryOnce() async {
        let learner = FakeLearner()
        let twice = [
            paymentSheet,
            DictationCorrection(
                heard: "my address", wrote: "PaymentSheet", wordRange: 6..<8, entryID: entry,
                reason: .heardAsSeveralWords, heardConfidence: 0.2),
        ]
        let pipeline = makePipeline(corrector: FakeCorrector(proposing: twice), learner: learner)

        await dictate(with: pipeline)

        #expect(learner.entries == [[entry]])
    }

    /// Each call is one whole-file write in the store, so a dictation costs one write however many entries fired.
    @Test("Counts every entry a dictation used in one call to the store")
    func countsTheEntriesInOneCall() async {
        let learner = FakeLearner()
        let two = [
            paymentSheet,
            DictationCorrection(
                heard: "my address", wrote: "MyAddress", wordRange: 6..<8, entryID: otherEntry,
                reason: .heardAsSeveralWords, heardConfidence: 0.2),
        ]
        let pipeline = makePipeline(corrector: FakeCorrector(proposing: two), learner: learner)

        await dictate(with: pipeline)

        #expect(learner.entries == [[entry, otherEntry]])
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
        #expect(learner.entries == [[]])
    }

    /// Issue 4275: a word the prompt made the recogniser spell right is used too, so the landed words reach the counter.
    @Test("Hands the counter the landed words when nothing was rewritten")
    func handsTheCounterTheLandedWords() async {
        let learner = FakeLearner()
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(inserter: inserter, learner: learner)

        await dictate(with: pipeline)

        #expect(learner.entries == [[]])
        #expect(learner.texts == inserter.received)
        #expect(learner.snippets.isEmpty)
    }

    /// A secret is no evidence a word is used, by the gate that keeps it out of History.
    @Test("Counts nothing from a secure field, not even an entry a correction applied")
    func countsNothingFromASecureField() async {
        let learner = FakeLearner()
        let pipeline = makePipeline(
            corrector: FakeCorrector(proposing: [paymentSheet]), learner: learner,
            context: FakeContextEngine(context: .fixture(isSecure: true)))

        await dictate(with: pipeline)

        #expect(learner.entries.isEmpty)
        #expect(learner.texts.isEmpty)
        #expect(learner.snippets.isEmpty)
    }

    /// A word earns its place by surviving a dictation; one that never landed proves nothing.
    @Test("Learns nothing from a dictation that never landed")
    func learnsNothingFromAFailedInsertion() async {
        let learner = FakeLearner()
        let pipeline = makePipeline(
            inserter: FakeTextInserter(.failure(.clipboardUnavailable)),
            corrector: FakeCorrector(proposing: [paymentSheet]), learner: learner)

        await dictate(with: pipeline)

        #expect(learner.entries.isEmpty)
    }

    /// Issue 1242: an unconfirmed paste is not proof the words reached the user, so nothing is counted yet.
    @Test("Counts nothing from an insertion the target never confirmed")
    func countsNothingFromAnUnconfirmedInsertion() async {
        let learner = FakeLearner()
        let pipeline = makePipeline(
            inserter: FakeTextInserter(.success(InsertionAttempt(.accessibility, arrival: .unconfirmed))),
            corrector: FakeCorrector(proposing: [paymentSheet]),
            snippets: FakeExpander(answering: { text in
                ExpandedTranscript(
                    text: text,
                    snippets: [SnippetUse(snippetID: snippet, matched: "x", expansion: "x")])
            }),
            learner: learner)

        await dictate(with: pipeline)

        #expect(learner.entries.isEmpty)
        #expect(learner.snippets.isEmpty)
    }

    /// This runs after the dictation is announced as inserted, so a refused note cannot be a failure.
    @Test("A store that refuses the note does not undo the dictation")
    func aRefusedNoteChangesNothing() async {
        let inserter = FakeTextInserter()
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
            cleaner: FakeTranscriptCleaner(tidying: \.capitalisedFirst, producedBy: .foundationModels),
            vocabulary: vocabulary)

        await dictate(with: pipeline)

        #expect(
            vocabulary.lessons == [
                FakeVocabulary.Lesson(
                    heard: heard, wrote: heard.capitalisedFirst, context: .fixture())
            ])
    }

    @Test("Does not learn private title words from a stale app context after insertion lands elsewhere")
    func doesNotLearnAgainstStaleApplicationContext() async {
        let vocabulary = FakeVocabulary()
        let appA = AppContext(
            applicationName: "Private App", bundleIdentifier: "com.example.a",
            documentName: "Secret project title")
        let landedInB = InsertionDestination(
            applicationName: "Public App", bundleIdentifier: "com.example.b")
        let pipeline = makePipeline(
            inserter: FakeTextInserter(.success(InsertionAttempt(.accessibility, destination: landedInB))),
            vocabulary: vocabulary,
            context: FakeContextEngine(context: appA))

        await dictate(with: pipeline)

        #expect(vocabulary.lessons.isEmpty)
        #expect(await pipeline.outcome?.insertedInto == "Public App")
        #expect(await pipeline.outcome?.insertedIntoIdentifier == "com.example.b")
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
            inserter: FakeTextInserter(.failure(.clipboardUnavailable)), vocabulary: vocabulary)

        await dictate(with: pipeline)

        #expect(vocabulary.lessons.isEmpty)
    }

    /// Issue 1242: the words may never have reached the user, so nothing is learnt from them yet.
    @Test("Teaches the dictionary nothing when the insertion goes unconfirmed")
    func learnsNothingFromAnUnconfirmedInsertion() async {
        let vocabulary = FakeVocabulary()
        let pipeline = makePipeline(
            inserter: FakeTextInserter(.success(InsertionAttempt(.accessibility, arrival: .unconfirmed))),
            vocabulary: vocabulary)

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
        let inserter = FakeTextInserter()
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
    /// One reading for every tidying step, so none sees another screen; the caret is read again to write.
    @Test("Reads the screen once for tidying and shows the same reading to everything")
    func readsTheScreenOnce() async {
        let context = FakeContextEngine(context: .fixture())
        let cleaner = FakeTranscriptCleaner(producedBy: .foundationModels)
        let corrector = FakeCorrector()
        let pipeline = makePipeline(cleaner: cleaner, corrector: corrector, context: context)

        await dictate(with: pipeline)

        #expect(await context.calls.count == 2)
        #expect(corrector.contexts == [.fixture()])
        #expect(cleaner.requests.map(\.context) == [.fixture()])
    }

    @Test("Scripting a new insertion point keeps a secure context secure")
    func setInsertionPointKeepsSecureFlag() async {
        let context = FakeContextEngine(context: .fixture(isSecure: true))

        await context.setInsertionPoint(InsertionPoint(precedingText: "because "))

        let after = await context.currentContext()
        #expect(after.isSecure)
        #expect(after.precedingText == "because ")
    }

    @Test("Hands the tidier the situation the screen resolves to, caret and all")
    func resolvesTheSituation() async {
        let context = FakeContextEngine(context: .fixture())
        await context.setInsertionPoint(InsertionPoint(precedingText: "because "))
        let cleaner = FakeTranscriptCleaner(producedBy: .foundationModels)
        let pipeline = makePipeline(cleaner: cleaner, context: context)

        await dictate(with: pipeline)

        let situation = cleaner.requests.first?.situation
        #expect(situation?.destination == .messaging)
        #expect(situation?.insertion.sentenceState == .midSentence)
        #expect(situation?.app == cleaner.requests.first?.context)
    }

    @Test("A lower-case dictionary spelling keeps its case when the caret moves to a sentence start")
    func pinnedSpellingSurvivesACaretMove() async {
        let context = CaretMovesBeforeWriting(
            read: .fixture(precedingText: "we ran "), write: .fixture(precedingText: ""))
        let inserter = FakeTextInserter()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(),
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: "kubectl apply the file"))),
            cleaner: FakeTranscriptCleaner(producedBy: .foundationModels),
            context: context, inserter: inserter, speechWords: { _ in ["kubectl"] },
            metrics: RecordingMetricsRecorder(), clock: ManualClock())

        await dictate(with: pipeline)

        #expect(inserter.received.last?.hasPrefix("kubectl apply") == true)
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

/// The screen as read when the key goes down, then a different caret once the words are ready to write.
private actor CaretMovesBeforeWriting: ContextEngine {
    private let read: AppContext
    private let write: AppContext
    private var reads = 0

    init(read: AppContext, write: AppContext) {
        self.read = read
        self.write = write
    }

    func currentContext() async -> AppContext {
        reads += 1
        return reads == 1 ? read : write
    }
}
