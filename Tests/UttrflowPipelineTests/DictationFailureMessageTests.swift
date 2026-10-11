// Tests that a failure's sentence is re-composed whenever its recovery changes, so the two never disagree.
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline

@Suite("A failure's sentence follows its recovery")
struct DictationFailureMessageTests {
    /// Every failure the pipeline turns into a retry from the kept recording, as `DictationPipeline.fail` decides.
    static var keptForRetry: [DictationFailure] {
        // The shortcut monitor and the permissions page raise these outside any dictation.
        let dictationFailures = FailureCatalogue.everyFailure.filter {
            !($0 is HotkeyError || $0 is PermissionError)
        }
        let all =
            dictationFailures.map { DictationFailure($0) }
            + [DictationFailure(CocoaError(.fileNoSuchFile))]
        return all.filter { $0.severity != .informational && ($0.recovery == nil || $0.recovery == .retry) }
    }

    @Test("a kept recording replaces the advice to try again", arguments: keptForRetry)
    func keptRecordingIsNamed(_ failure: DictationFailure) {
        let kept = failure.offering(.retryFromRecording)

        #expect(!kept.message.localizedCaseInsensitiveContains("try again"), "\(kept.message)")
        #expect(kept.message.contains("recording is kept"), "\(kept.message)")
        #expect(kept.message.hasPrefix(failure.cause))
    }

    @Test("the pipeline's retry of a kept recording composes the same sentence")
    func pipelineRetryComposes() {
        let failure = DictationFailure(SpeechEngineError.transcriptionFailed(description: ""))
        let recording = UUID()
        let kept = failure.offeringRetry(of: recording)

        #expect(kept.message == failure.offering(.retryFromRecording).message)
        #expect(kept.keptRecording == recording)
        #expect(!kept.message.localizedCaseInsensitiveContains("try again"), "\(kept.message)")
    }

    @Test("offering the error's own recovery keeps its sentence")
    func ownRecoveryKeepsTheSentence() {
        let failure = DictationFailure(SpeechEngineError.transcriptionFailed(description: ""))

        #expect(failure.offering(.retry) == failure)
    }

    @Test("the announcement reads the composed sentence")
    func announcementMatchesTheDock() {
        let kept = DictationFailure(SpeechEngineError.recogniserTimedOut).offering(.retryFromRecording)
        let announcement = DictationPresenter.announcement(for: .failed(kept))

        #expect(announcement?.text.hasPrefix(kept.message) == true)
    }
}
