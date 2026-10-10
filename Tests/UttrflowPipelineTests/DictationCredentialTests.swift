import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A vocabulary that remembers every lesson it is offered.
private final class LessonLog: VocabularyLearning, Sendable {
    private let lessons = Mutex<[String]>([])

    func learn(
        heard: String, wrote: String, seeing context: AppContext
    ) async throws(DictationChangeError) {
        lessons.withLock { $0.append(wrote) }
    }

    var offered: [String] { lessons.withLock { $0 } }
}

/// Invented credential-shaped dictations.
private let credentials = [
    "the access key id is ASIAY34FZKBOKMUTVV7A",
    "export AWS_SECRET_ACCESS_KEY=Qv7RkT2mXeL9pAz4NbHc8FwJdY3gS6uH",
    "postgres://deploy:Qv7RkT2mXeL9pAz4@db.example.invalid:5432/app",
    "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJleGFtcGxlIn0.c2lnbmF0dXJlZXhhbXBsZQ",
    "mysql -u root -pExampleS3cret appdb",
]

/// Invented ordinary developer dictations, which must stay in History.
private let ordinary = [
    "rename the function to fetchUserProfile and add a test",
    "the build fails on line 42 because the import is missing",
    "open a pull request against main when the tests pass",
    "set the timeout to thirty seconds in the config file",
    "the container listens on port 8080 behind the proxy",
]

private func dictate(
    _ words: String, vocabulary: any VocabularyLearning = NoTextChanges()
) async
    -> DictationState
{
    let pipeline = DictationPipeline(
        capture: FakeAudioCaptureEngine(),
        speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: words))),
        cleaner: FakeTranscriptCleaner(),
        context: FakeContextEngine(context: .fixture()),
        inserter: FakeTextInserter(.success(InsertionAttempt(.pasteboard))),
        vocabulary: vocabulary,
        clock: ManualClock())
    await pipeline.startRecording()
    await pipeline.finishRecording()
    return await pipeline.currentState
}

@Suite("A credential-shaped dictation is inserted but kept nowhere")
struct DictationCredentialTests {
    @Test("a credential is inserted and leaves no words to keep", arguments: credentials)
    func credentialIsWithheld(_ words: String) async {
        let state = await dictate(words)

        guard case .inserted(let outcome) = state else {
            Issue.record("expected an insertion, got \(state)")
            return
        }
        #expect(!outcome.text.isEmpty)
        #expect(outcome.wordsToKeep == nil)
    }

    @Test("the dictionary learns nothing from a credential", arguments: credentials)
    func learnsNothing(_ words: String) async {
        let vocabulary = LessonLog()
        _ = await dictate(words, vocabulary: vocabulary)

        #expect(vocabulary.offered.isEmpty)
    }

    @Test("ordinary developer dictation is still kept", arguments: ordinary)
    func ordinaryIsKept(_ words: String) async {
        let state = await dictate(words)

        guard case .inserted(let outcome) = state else {
            Issue.record("expected an insertion, got \(state)")
            return
        }
        #expect(outcome.wordsToKeep == outcome.text)
        #expect(outcome.changes.heard == words)
    }

    @Test("a failed credential dictation salvages nothing a history may keep")
    func failureSalvagesNothing() {
        let failure = DictationFailure(
            message: "x", recovery: .copyTranscript, severity: .recoverable, transcript: credentials[0])

        #expect(failure.wordsToKeep == nil)
    }
}
