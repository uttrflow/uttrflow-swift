// Tests that a failed dictation's History record keeps the private-window finding.

import Foundation
import Testing
import UttrflowCore
import UttrflowHistory
import UttrflowPipeline

@testable import Uttrflow

@Suite("History records of failed dictations")
struct DictationRecordMappingPrivateTests {
    @Test("a failed dictation from a private window is recorded as private, and an ordinary one is not")
    func failedRecordKeepsPrivateWindow() {
        let failure = DictationFailure(
            message: "Nothing took the text.", recovery: .copyTranscript, severity: .recoverable,
            transcript: "ship the draft on friday")
        let state = { (isPrivate: Bool) in DictationState.failed(failure.markingPrivate(isPrivate)) }
        let record = { (isPrivate: Bool) in
            DictationRecordMapping.record(for: state(isPrivate), when: Date(), id: UUID())
        }
        #expect(record(true)?.fromPrivateWindow == true)
        #expect(record(false)?.fromPrivateWindow == false)
    }

    @Test("a failed dictation meant for an app left out of History is not kept, and one meant elsewhere is")
    func failedRecordFollowsTheAppItWasMeantFor() {
        let failure = DictationFailure(
            message: "Nothing took the text.", recovery: .copyTranscript, severity: .recoverable,
            transcript: "ship the draft on friday")
        let keeping = HistoryKeeping(excludedApplications: ["com.example.Records"])
        let record = { (application: String?) in
            DictationRecordMapping.record(
                for: .failed(failure.markingDestination(application)), when: Date(), id: UUID(),
                keeping: keeping)
        }
        #expect(record("com.example.records") == nil)
        #expect(record("com.example.notes")?.text == "ship the draft on friday")
        #expect(record(nil)?.text == "ship the draft on friday")
        let rebuilt = failure.markingDestination("com.example.records").markingSecure(false).offering(.retry)
        #expect(rebuilt.meantForApplication == "com.example.records")
    }
}
