import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// Quotation, dash and line checks read code, terminal and line-by-line text by their own rules.
@Suite("The guard on code, terminal and line-by-line text")
struct GuardDestinationShapeTests {
    @Test("a string the speaker opened and closed by saying quote is not an invented quotation")
    func spokenQuotesAreTheSpeakers() {
        let original = "git commit -m quote wip quote"
        #expect(
            MeaningPreservationGuard.symbolVerdict(original: original, rewritten: "git commit -m \"wip\"")
                .isAccepted)
        #expect(
            !MeaningPreservationGuard.symbolVerdict(
                original: original, rewritten: "git commit -m \"git\" wip"
            )
            .isAccepted)
    }

    @Test("a quoted string may write its spoken symbol names as symbols, never add a word")
    func quotedStringKeepsItsWords() {
        let original = "log(\"user percent s logged in\")"
        #expect(
            MeaningPreservationGuard.symbolVerdict(
                original: original, rewritten: "log(\"user %s logged in\")"
            )
            .isAccepted)
        #expect(
            !MeaningPreservationGuard.symbolVerdict(
                original: original, rewritten: "log(\"admin %s logged in\")"
            ).isAccepted)
    }

    @Test("a spoken dash is answered by a hyphen, and dropping it is still refused")
    func hyphenAnswersSpokenDash() {
        let draft = CleaningPipeline.standard.run(
            Draft(keepingLineBreaks: "removed the dash dash legacy dash sync flag"))
        #expect(draft.text == "Removed the --legacy-sync flag.")
        #expect(
            MeaningPreservationGuard.spokenPunctuationVerdict(
                draft: draft, rewritten: "Removed the --legacy-sync flag"
            ).isAccepted)
        #expect(
            !MeaningPreservationGuard.spokenPunctuationVerdict(
                draft: draft, rewritten: "Removed the legacy sync flag"
            ).isAccepted)
    }

    @Test("notes laid out line by line are not a run-on, however long the whole")
    func linesEndLikeSentences() {
        let line = "action item: send the revised budget to the team by friday morning"
        let text = Array(repeating: line, count: 5).joined(separator: "\n")
        let draft = Draft(keepingLineBreaks: text)
        let verdict = MeaningPreservationGuard().verdict(draft: draft, rewritten: text)
        #expect(verdict.isAccepted)
    }
}
