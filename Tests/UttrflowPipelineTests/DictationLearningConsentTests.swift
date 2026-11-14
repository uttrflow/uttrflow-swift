import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A vocabulary that remembers every lesson it is offered.
private final class RememberingVocabulary: VocabularyLearning, Sendable {
    private let lessons = Mutex<[String]>([])

    func learn(
        heard: String, wrote: String, seeing context: AppContext
    ) async throws(DictationChangeError) {
        lessons.withLock { $0.append(wrote) }
    }

    var offered: [String] { lessons.withLock { $0 } }
}

/// Consent holding one answer for every application.
private struct OneAnswer: LearningConsent {
    let answer: ConsentState

    func state(of bundleIdentifier: String?) -> ConsentState { answer }
}

private let words = "ship the draft on friday"

private func lessons(
    given consent: any LearningConsent, isSecure: Bool = false, window: String = "#engineering"
) async -> [String] {
    await dictate(given: consent, isSecure: isSecure, window: window).lessons
}

/// One dictation into a window with this title, returning what the dictionary was offered and the outcome.
private func dictate(
    given consent: any LearningConsent, isSecure: Bool = false, window: String
) async -> (lessons: [String], outcome: DictationOutcome?) {
    let vocabulary = RememberingVocabulary()
    let pipeline = DictationPipeline(
        capture: FakeAudioCaptureEngine(),
        speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: words))),
        cleaner: FakeTranscriptCleaner(),
        context: FakeContextEngine(context: .fixture(documentName: window, isSecure: isSecure)),
        inserter: FakeTextInserter(.success(InsertionAttempt(.pasteboard))),
        vocabulary: vocabulary,
        consent: consent,
        clock: ManualClock())
    await pipeline.startRecording()
    await pipeline.finishRecording()
    await pipeline.settlePostInsertion()
    guard case .inserted(let outcome) = await pipeline.currentState else { return (vocabulary.offered, nil) }
    return (vocabulary.offered, outcome)
}

@Suite("Dictation learns under the same per-application consent as typing capture")
struct DictationLearningConsentTests {
    @Test("an application the user declined teaches the dictionary nothing")
    func declinedLearnsNothing() async {
        #expect(await lessons(given: OneAnswer(answer: .declined)).isEmpty)
    }

    @Test("an application never asked about is learned from, since nothing leaves this Mac")
    func unknownLearns() async {
        #expect(await lessons(given: OneAnswer(answer: .unknown)).count == 1)
    }

    @Test("an application the user allowed is learned from")
    func allowedLearns() async {
        #expect(await lessons(given: OneAnswer(answer: .allowed)).count == 1)
    }

    @Test("a secure field teaches nothing even where the user allowed learning")
    func secureStaysExcluded() async {
        #expect(await lessons(given: OneAnswer(answer: .allowed), isSecure: true).isEmpty)
    }

    @Test(
        "a window that names itself private teaches nothing even where the user allowed learning",
        arguments: ["Example (Incognito)", "Example - InPrivate", "Example - Private Browsing"])
    func privateWindowLearnsNothing(title: String) async {
        let refused = await dictate(given: OneAnswer(answer: .allowed), window: title)
        #expect(refused.lessons.isEmpty)
        #expect(refused.outcome?.fromPrivateWindow == true)
    }

    @Test("an ordinary window of the same application is still learned from")
    func ordinaryWindowLearns() async {
        let ordinary = await dictate(given: OneAnswer(answer: .allowed), window: "Example - Browser")
        #expect(ordinary.lessons.count == 1)
        #expect(ordinary.outcome?.fromPrivateWindow == false)
    }

    @Test("a retried recording from a private window teaches nothing, though its identity has no title")
    func retriedPrivateRecordingLearnsNothing() async {
        let vocabulary = RememberingVocabulary()
        let kept = KeptRecording(
            id: UUID(), when: Date(), duration: .seconds(1),
            destination: AppContext.fixture().identity, fromPrivateWindow: true)
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(),
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: words))),
            cleaner: FakeTranscriptCleaner(),
            context: FakeContextEngine(context: .fixture()),
            inserter: FakeTextInserter(.success(InsertionAttempt(.pasteboard))),
            vocabulary: vocabulary,
            consent: OneAnswer(answer: .allowed),
            recordings: FakeRecordingKeeper(waiting: [kept]),
            clock: ManualClock())
        #expect(await pipeline.retry(kept.id))
        guard case .inserted(let outcome) = await pipeline.currentState else {
            Issue.record("expected the retry to land")
            return
        }
        #expect(outcome.fromPrivateWindow)
        #expect(vocabulary.offered.isEmpty)
    }

    @Test("no later read, timed out or ordinary, clears the private window an earlier read found")
    func timedOutFinalReadKeepsPrivateWindow() async throws {
        let context = FakeContextEngine(context: .fixture(documentName: "Example - Private Browsing"))
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(),
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: words))),
            cleaner: FakeTranscriptCleaner(),
            context: context,
            inserter: FakeTextInserter(.success(InsertionAttempt(.pasteboard))),
            clock: ManualClock())
        await pipeline.startRecording()
        try await eventually { await pipeline.earlyReadsSettled == 1 }
        #expect(await pipeline.destinationIsPrivate)

        await context.setContext(AppContext(bundleIdentifier: DestinationRules.slack, unavailable: .timedOut))
        _ = await pipeline.contextFor(.insert)
        #expect(await pipeline.destinationIsPrivate)

        await context.setContext(.fixture(documentName: "Example - Browser"))
        _ = await pipeline.contextFor(.insert)
        #expect(await pipeline.destinationIsPrivate)
        await pipeline.cancel()
    }

    @Test("a finished recording kept for a fix brings its private-window finding to a retry")
    func retriedFinishedPrivateRecordingLearnsNothing() async {
        let vocabulary = RememberingVocabulary()
        let kept = KeptRecording(
            id: UUID(), when: Date(), duration: .seconds(1),
            destination: AppContext.fixture().identity, fromPrivateWindow: true)
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(),
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: words))),
            cleaner: FakeTranscriptCleaner(),
            context: FakeContextEngine(context: .fixture()),
            inserter: FakeTextInserter(.success(InsertionAttempt(.pasteboard))),
            vocabulary: vocabulary,
            consent: OneAnswer(answer: .allowed),
            recordings: FakeRecordingKeeper(finished: [kept]),
            clock: ManualClock())
        #expect(await pipeline.retry(kept.id))
        guard case .inserted(let outcome) = await pipeline.currentState else {
            Issue.record("expected the retry to land")
            return
        }
        #expect(outcome.fromPrivateWindow)
        #expect(vocabulary.offered.isEmpty)
    }

    @Test(
        "a switch to a private window of the same application before the write marks the dictation and its recording"
    )
    func insertionTimePrivateWindowCounts() async throws {
        let vocabulary = RememberingVocabulary()
        let recording = KeptRecording(id: UUID(), when: Date(), duration: .seconds(1))
        let keeper = FakeRecordingKeeper(current: recording)
        let context = FakeContextEngine(context: .fixture(documentName: "Example - Browser"))
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(),
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: words))),
            cleaner: FakeTranscriptCleaner(),
            context: context,
            inserter: FakeTextInserter(.success(InsertionAttempt(.accessibility, arrival: .confirmed))),
            vocabulary: vocabulary,
            consent: OneAnswer(answer: .allowed),
            recordings: keeper,
            clock: ManualClock())
        await pipeline.startRecording()
        try await eventually { await pipeline.earlyReadsSettled == 1 }
        await context.setContext(.fixture(documentName: "Example - Private Browsing"))
        await pipeline.finishRecording()
        await pipeline.settlePostInsertion()
        guard case .inserted(let outcome) = await pipeline.currentState else {
            Issue.record("expected the dictation to land")
            return
        }
        #expect(outcome.fromPrivateWindow)
        #expect(vocabulary.offered.isEmpty)
        #expect(try await keeper.audio(of: recording.id).recording?.fromPrivateWindow == true)
    }

    @Test("a dictation that fails in a private window says so, so History never learns from it")
    func failedPrivateDictationIsMarked() async {
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(),
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: words))),
            cleaner: FakeTranscriptCleaner(),
            context: FakeContextEngine(context: .fixture(documentName: "Example - Private Browsing")),
            inserter: FakeTextInserter(.failure(.noFocusedTextField)),
            clock: ManualClock())
        await pipeline.startRecording()
        await pipeline.finishRecording()
        await pipeline.settlePostInsertion()
        guard case .failed(let failure) = await pipeline.currentState else {
            Issue.record("expected the dictation to fail")
            return
        }
        #expect(failure.fromPrivateWindow)
        #expect(failure.offering(.retry).fromPrivateWindow)
        #expect(failure.markingSecure(false).fromPrivateWindow)
    }

    @Test("the switch in Settings, turned off, stops learning even where the user allowed it")
    func switchOffLearnsNothing() async {
        let off = SwitchedLearningConsent(isOn: { false }, answers: OneAnswer(answer: .allowed))
        #expect(await lessons(given: off).isEmpty)
    }

    @Test("the switch in Settings, left on, leaves each application's answer in charge")
    func switchOnDefersToTheApplication() async {
        let unknown = SwitchedLearningConsent(isOn: { true }, answers: OneAnswer(answer: .unknown))
        let declined = SwitchedLearningConsent(isOn: { true }, answers: OneAnswer(answer: .declined))
        #expect(await lessons(given: unknown).count == 1)
        #expect(await lessons(given: declined).isEmpty)
    }

    @Test("only a refusal stops dictation learning")
    func theDefaultIsWrittenOnce() {
        #expect(ConsentState.allCases.filter { !$0.dictationMayLearn } == [.declined])
    }
}
