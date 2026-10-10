import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("The notation evidence rule")
struct NotationEvidenceTests {
    @Test("reads a command line and a caret in code as evidence, and a comment or prose body against")
    func screenCues() {
        #expect(
            NotationEvidence.applicability(destination: .terminal, region: .unrecognised)
                == .evidenced(confidence: 1, by: [.commandLine]))
        for region in [CaretStructure.Region.code, .string] {
            #expect(
                NotationEvidence.applicability(destination: .codeEditor, region: region)
                    == .evidenced(confidence: 1, by: [.caretInCode]))
        }
        for region in [CaretStructure.Region.comment, .prose] {
            #expect(
                NotationEvidence.applicability(destination: .codeEditor, region: region)
                    == .ruledOut(by: .caretInProse))
        }
        #expect(
            NotationEvidence.applicability(destination: .codeEditor, region: .unrecognised) == .noEvidence)
        #expect(NotationEvidence.applicability(destination: .sqlEditor, region: .code) == .noEvidence)
    }

    @Test("rules the notation out when the speech holds a prose word")
    func speechCues() {
        let screen = Applicability(cues: [.caretInCode])
        #expect(
            NotationEvidence.applicability(of: ["the", "dot", "product"], given: screen)
                == .ruledOut(by: .proseWord))
        #expect(
            NotationEvidence.applicability(of: ["our", "costs", "dot"], given: screen)
                == .ruledOut(by: .proseWord))
        #expect(NotationEvidence.applicability(of: ["this", "dot", "count"], given: screen) == screen)
        #expect(NotationEvidence.applicability(of: ["x", "equals", "one"], given: screen) == screen)
    }

    @Test("never activates on speech alone: a prose-free utterance with no screen cue stays words")
    func speechAloneAbstains() {
        let evidence = NotationEvidence.applicability(of: ["x", "equals", "one"], given: .noEvidence)
        #expect(!evidence.activates(at: NotationEvidence.activationThreshold))
    }
}
