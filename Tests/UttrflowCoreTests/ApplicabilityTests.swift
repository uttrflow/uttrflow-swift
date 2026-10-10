import Testing

@testable import UttrflowCore

@Suite("Applicability")
struct ApplicabilityTests {
    @Test("abstains when no cue was read")
    func noCueAbstains() {
        let applicability = Applicability(cues: [])
        #expect(applicability == .noEvidence)
        #expect(!applicability.activates(at: 0))
        #expect(applicability.cues.isEmpty)
    }

    @Test("activates on a cue for the notation at its weight")
    func cueForActivates() {
        let applicability = Applicability(cues: [.caretInCode])
        #expect(applicability == .evidenced(confidence: 1, by: [.caretInCode]))
        #expect(applicability.activates(at: 1))
        #expect(applicability.cues == [.caretInCode])
    }

    @Test("is ruled out by any cue against, whatever speaks for it", arguments: [AdapterCue.caretInProse, .proseWord])
    func cueAgainstRulesOut(against: AdapterCue) {
        let applicability = Applicability(cues: [.commandLine]).adding([against])
        #expect(applicability == .ruledOut(by: against))
        #expect(!applicability.activates(at: 0))
        #expect(applicability.cues == [against])
    }

    @Test("caps the confidence of several cues at one")
    func confidenceIsCapped() {
        #expect(
            Applicability(cues: [.caretInCode, .commandLine])
                == .evidenced(confidence: 1, by: [.caretInCode, .commandLine]))
    }
}
