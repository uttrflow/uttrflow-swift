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

    @Test("a mark the pass moved off a spoken word it then dropped is required once, not twice")
    func movedMarkCountsOnce() {
        let app = AppContext()
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .codeEditor)
        let draft = CleaningPipeline.beforeModel(for: .standard(for: situation), situation: situation)
            .run(Draft(text: "log dot info open paren quote user close quote close paren"))
        #expect(
            MeaningPreservationGuard.spokenPunctuationVerdict(
                draft: draft, rewritten: "log.info(\"user\")"
            ).isAccepted)
        #expect(
            !MeaningPreservationGuard.spokenPunctuationVerdict(
                draft: draft, rewritten: "log.info\"user\")"
            ).isAccepted)
    }

    @Test("a spoken code symbol written as its mark on its own is the mark, and dropping it is still refused")
    func loneCodeMarkStandsForItsName() {
        let app = AppContext()
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .terminal)
        let draft = CleaningPipeline.beforeModel(for: .standard(for: situation), situation: situation)
            .run(Draft(text: "docker build dash dash no dash cache dot"))
        #expect(draft.text == "docker build --no-cache dot")
        let verdict = { (rewritten: String) in
            MeaningPreservationGuard().verdict(draft: draft, rewritten: rewritten)
        }
        #expect(verdict("docker build --no-cache .").isAccepted)
        #expect(!verdict("docker build --no-cache").isAccepted)
        #expect(
            !MeaningPreservationGuard().verdict(
                draft: Draft(text: "it ends with a period"), rewritten: "it ends with a ."
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
