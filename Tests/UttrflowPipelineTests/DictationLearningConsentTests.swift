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

    func state(of bundleIdentifier: String?) async -> ConsentState { answer }
}

private let words = "ship the draft on friday"

private func lessons(given consent: any LearningConsent, isSecure: Bool = false) async -> [String] {
    let vocabulary = RememberingVocabulary()
    let pipeline = DictationPipeline(
        capture: FakeAudioCaptureEngine(),
        speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: words))),
        cleaner: FakeTranscriptCleaner(),
        context: FakeContextEngine(context: .fixture(isSecure: isSecure)),
        inserter: FakeTextInserter(.success(InsertionAttempt(.pasteboard))),
        vocabulary: vocabulary,
        consent: consent,
        clock: ManualClock())
    await pipeline.startRecording()
    await pipeline.finishRecording()
    return vocabulary.offered
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

    @Test("only a refusal stops dictation learning")
    func theDefaultIsWrittenOnce() {
        #expect(ConsentState.allCases.filter { !$0.dictationMayLearn } == [.declined])
    }
}
