import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("SpokenPunctuationPass")
struct SpokenPunctuationPassTests {
    private let sut = SpokenPunctuationPass()

    @Test(
        "turns a mark said by name into the mark on the word before it",
        arguments: [
            ("add milk comma eggs comma and bread", "add milk, eggs, and bread"),
            ("is it ready question mark", "is it ready?"),
            ("ship it full stop", "ship it."),
            ("ship it period", "ship it."),
            ("wow exclamation mark", "wow!"),
            ("wow exclamation point", "wow!"),
            ("two things colon milk", "two things: milk"),
            ("milk semicolon eggs", "milk; eggs"),
            ("milk semi colon eggs", "milk; eggs"),
            ("ready. question mark", "ready?"),
            ("milk, comma eggs", "milk, eggs"),
            ("done comma next", "done, next"),
        ]
    )
    func attachesMarks(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "ends a sentence with a spoken full stop only where the text closes",
        arguments: [
            ("ship it period new line next", "ship it. new line next"),
            ("ship it full stop new paragraph next", "ship it. new paragraph next"),
            ("he said open quote ship it period close quote", "he said \"ship it.\""),
            ("did you finish the trial period question mark", "did you finish the trial period?"),
            ("the trial period comma which ended", "the trial period, which ended"),
        ]
    )
    func fullStopsOnlyWhereTheTextCloses(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("ends a sentence with a spoken full stop before a layout mark already placed")
    func fullStopBeforeLayoutMark() {
        let draft = Draft(words: ["ship", "it", "period", "\n", "next"].map { Draft.Word($0) })
        #expect(sut.apply(draft).text == "ship it.\nnext")
    }

    @Test("wraps the words between open quote and close quote")
    func quotes() {
        #expect(cleaned("he said open quote hello there close quote", by: sut) == "he said \"hello there\"")
    }

    @Test("joins the words around a hyphen, and spaces a dash")
    func hyphenAndDash() {
        #expect(cleaned("a well hyphen known bug", by: sut) == "a well-known bug")
        #expect(cleaned("we went home dash it was late", by: sut) == "we went home \u{2014} it was late")
    }

    /// "Dash" and "hyphen" are verbs too, and the particle after them is what says which was meant.
    @Test(
        "leaves dash and hyphen as words when a particle follows them",
        arguments: [
            "we should dash off a quick note to the client",
            "she had to dash out before the standup",
            "let me dash over to the other building",
            "hyphen in the name is fine",
        ]
    )
    func leavesTheVerb(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "leaves a mark that is mentioned rather than used",
        arguments: [
            "put a comma after the greeting",
            "the period of time",
            "add a period",
            "with no comma",
            "comma",
            "comma first",
            "a long period of time",
            "this period was hard",
            "insert a colon",
            "say open quote",
            "a well hyphen",
            "the Dash app crashed",
            "a dash of salt",
        ]
    )
    func leavesMentions(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "leaves a full stop or period that is not at the end, and a hyphen or dash that is",
        arguments: [
            "the trial period ended last week",
            "ship it period next thing",
            "done full stop next",
            "we made it home dash",
            "well hyphen new line known",
            "we went home dash new line late",
        ]
    )
    func leavesMisplacedMarks(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("records the mark on the word before and the name as removed")
    func provenance() {
        let draft = sut.apply(Draft(text: "milk comma eggs"))
        #expect(draft.words[0].state == .replaced(by: SpokenPunctuationPass.id, from: "milk"))
        #expect(draft.words[1].state == .removed(by: SpokenPunctuationPass.id))
        #expect(draft.words[2].state == .kept)
    }
}
