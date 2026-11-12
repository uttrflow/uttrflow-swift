// Tests that the style and retry evidence writers share one rule for which dictations may teach them.

import Testing
import UttrflowCore
import UttrflowPipeline

@testable import Uttrflow

@Suite("Which dictations may add evidence rows")
struct EvidenceEligibilityTests {
    @Test("an ordinary dictation teaches the evidence ledger")
    func ordinaryTeaches() {
        #expect(DictationOutcome(text: "ship it", method: .pasteboard, cleanedBy: .rules).teachesEvidence)
    }

    @Test("a secure field, a private window or a retried recording teaches nothing")
    func refusedCasesTeachNothing() {
        let text = "ship it"
        let refused = [
            DictationOutcome(text: text, method: .pasteboard, cleanedBy: .rules, intoSecureField: true),
            DictationOutcome(text: text, method: .pasteboard, cleanedBy: .rules, fromPrivateWindow: true),
            DictationOutcome(text: text, method: .pasteboard, cleanedBy: .rules, fromRecording: true),
        ]
        #expect(refused.allSatisfy { !$0.teachesEvidence })
    }
}
