import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Negation anchors after spoken marks")
struct NegationMarkAnchorTests {
    @Test("accepts the unchanged CSS value beside consumed punctuation names")
    func acceptsValueBesideConsumedMarks() {
        let draft = CleaningPipeline.standard.run(
            Draft(keepingLineBreaks: "display colon none semicolon close brace"))
        #expect(MeaningPreservationGuard().verdict(draft: draft, rewritten: "display: none;}").isAccepted)
    }

    @Test("refuses deleting or replacing the CSS negating value", arguments: ["display: block;}", "display: ;}"])
    func refusesChangedValue(rewritten: String) {
        let draft = CleaningPipeline.standard.run(
            Draft(keepingLineBreaks: "display colon none semicolon close brace"))
        #expect(!MeaningPreservationGuard().verdict(draft: draft, rewritten: rewritten).isAccepted)
    }

    @Test("refuses a genuine negation moved across a content word")
    func refusesMovedNegation() {
        #expect(
            MeaningPreservationGuard.grammarVerdict(
                kept: "I did not tell Ada to call Ben",
                rewritten: "I did tell Ada not to call Ben.")
                == .rejected(reason: "the rewrite moved a negation", kind: .negationMoved))
    }
}
