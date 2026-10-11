import Foundation
import Testing
import UttrflowCore
import UttrflowPipeline

@testable import Uttrflow

@Suite("Dictation result retention is independent of interface scheduling")
struct DockLingerPolicyTests {
    @Test(
        "unfinished states have no dismissal interval",
        arguments: [
            DictationState.idle, .recording, .transcribing, .tidying, .inserting(into: nil),
        ])
    func unfinishedStatesRemainVisible(_ state: DictationState) {
        #expect(DockLingerPolicy.linger(after: state) == nil)
        #expect(DockLingerPolicy.linger(after: state, voiceOverEnabled: true) == nil)
    }

    @Test("a discarded recording lingers longer only when restore is available")
    func discardedRecordingRetention() {
        let discarded = DictationDiscard(spokenFor: .seconds(90), keptRecording: nil)
        let restorable = DictationDiscard(spokenFor: .seconds(90), keptRecording: UUID())
        #expect(DockLingerPolicy.linger(after: .discarded(discarded)) == .seconds(2))
        #expect(DockLingerPolicy.linger(after: .discarded(restorable)) == .seconds(10))
        #expect(DockLingerPolicy.linger(after: .executed("Example action.")) == .seconds(2))
    }

    @Test("a completed insertion uses the paste requirement rather than VoiceOver", arguments: [false, true])
    func completedInsertionRetention(voiceOver: Bool) {
        let typed = DictationOutcome(text: "Example text.", method: .accessibility, cleanedBy: .rules)
        let copied = DictationOutcome(text: "Example text.", method: .clipboard, cleanedBy: .rules)
        #expect(DockLingerPolicy.linger(after: .inserted(typed), voiceOverEnabled: voiceOver) == .seconds(2))
        #expect(
            DockLingerPolicy.linger(after: .inserted(copied), voiceOverEnabled: voiceOver) == .seconds(10))
    }

    @Test("VoiceOver extends actionable failures but not informational or nonactionable notices")
    func recoveryControlsVoiceOverRetention() {
        let failure = DictationFailure(message: "Example notice.", recovery: .retry, severity: .recoverable)
        let noRecovery = DictationFailure(message: "Example notice.", recovery: nil, severity: .recoverable)
        let informational = DictationFailure(
            message: "Example notice.", recovery: .retry, severity: .informational)
        #expect(DockLingerPolicy.linger(after: .failed(failure)) == .seconds(10))
        #expect(DockLingerPolicy.linger(after: .failed(failure), voiceOverEnabled: true) == .seconds(20))
        #expect(DockLingerPolicy.linger(after: .failed(noRecovery), voiceOverEnabled: true) == .seconds(10))
        #expect(DockLingerPolicy.linger(after: .failed(informational), voiceOverEnabled: true) == .seconds(2))
    }
}
