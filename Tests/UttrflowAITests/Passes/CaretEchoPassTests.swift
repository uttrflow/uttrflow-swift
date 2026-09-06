import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("CaretEchoPass")
struct CaretEchoPassTests {
    private func pass(_ preceding: String?) -> CaretEchoPass {
        CaretEchoPass(state: InsertionPoint.sentenceState(before: preceding), precedingText: preceding)
    }

    @Test(
        "takes back the caret's text when the model repeats it, however it cases or punctuates it",
        arguments: [
            (
                "The build was red this morning because ",
                "The build was red this morning because the deployment script timed out",
                "the deployment script timed out"
            ),
            (
                "Following up on ", "Following up on the quote you sent last week",
                "the quote you sent last week"
            ),
            (
                "The build was red because ", "the build was red because, the deploy failed",
                "the deploy failed"
            ),
            (
                "The build was red because ", "The build was red because — the deploy failed",
                "the deploy failed"
            ),
            ("He said \"wait\" and ", "he said 'wait' and left", "left"),
        ])
    func stripsEcho(preceding: String, answer: String, expected: String) {
        #expect(cleaned(answer, by: pass(preceding)) == expected)
    }

    @Test("takes back the cut tail the prompt quoted, with or without its ellipsis")
    func stripsQuotedTail() throws {
        let preceding = String(repeating: "word ", count: 30) + "end because "
        let quoted = try #require(PromptBuilder.caretText(InsertionPoint(precedingText: preceding)))
        #expect(quoted.hasPrefix("…word") && quoted.count < preceding.count)
        #expect(cleaned("\(quoted) the deploy failed", by: pass(preceding)) == "the deploy failed")
        #expect(
            cleaned("\(quoted.dropFirst()) the deploy failed", by: pass(preceding)) == "the deploy failed")
        #expect(cleaned("\(preceding)the deploy failed", by: pass(preceding)) == "the deploy failed")
    }

    @Test("strips only the whole preceding text, never a partial match")
    func keepsPartialMatches() {
        #expect(cleaned("then we can go", by: pass("and then ")) == "then we can go")
        #expect(
            cleaned("because it was late", by: pass("The build was red because ")) == "because it was late")
        #expect(cleaned("the build was red", by: pass("The build was red because ")) == "the build was red")
    }

    @Test("leaves a one-word caret alone, since a legitimate first word can equal it")
    func oneWordCaret() {
        #expect(cleaned("hi everyone", by: pass("Hi ")) == "hi everyone")
    }

    @Test("does nothing at the start of a sentence, where the field will not say, or after a line break")
    func inactiveElsewhere() {
        #expect(cleaned("Done. the next step", by: pass("Done. ")) == "Done. the next step")
        #expect(cleaned("and then we go", by: pass(nil)) == "and then we go")
        let broken = Draft(words: ["and", "\n", "then", "we", "go"].map { Draft.Word($0) })
        #expect(pass("and then ").apply(broken).text == "and\nthen we go")
    }

    @Test("drops the line break the model put after an echo that was a line of its own")
    func echoOnItsOwnLine() {
        let own = Draft(keepingLineBreaks: "Following up on\nthe quote you sent")
        #expect(pass("Following up on ").apply(own).text == "the quote you sent")
    }

    @Test("records what it removed, and finishes into a lower-case continuation through afterModel")
    func provenanceAndPipeline() {
        let draft = pass("Following up on ").apply(Draft(text: "Following up on the quote"))
        #expect(draft.removed.map(\.heard) == ["Following", "up", "on"])
        #expect(draft.words[0].state == .removed(by: CaretEchoPass.id))

        let mail = AppContext(documentName: "Re: Quote", precedingText: "Following up on ")
        let situation = Situation(app: mail, insertion: mail.insertionPoint, destination: .email)
        let finished = CleaningPipeline.afterModel(for: .standard(for: .email), situation: situation)
        #expect(
            finished.run(Draft(keepingLineBreaks: "Following up on the quote you sent last week")).text
                == "the quote you sent last week.")

        let note = AppContext(
            documentName: "Incident log", precedingText: "The build was red this morning because ")
        let notes = Situation(app: note, insertion: note.insertionPoint, destination: .document)
        let document = CleaningPipeline.afterModel(for: .standard(for: .document), situation: notes)
        #expect(
            document.run(
                Draft(
                    keepingLineBreaks:
                        "The build was red this morning because the deployment script timed out")
            ).text == "the deployment script timed out.")
    }
}
