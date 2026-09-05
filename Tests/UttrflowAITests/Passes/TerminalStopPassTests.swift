import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("TerminalStopPass")
struct TerminalStopPassTests {
    private let sut = TerminalStopPass()
    private let never = TerminalStopPass(policy: .never)
    private let short = TerminalStopPass(policy: .offForShortMessages(sentences: 2))

    @Test(
        "finishes a sentence that has no ending",
        arguments: [("hello there", "hello there."), ("42", "42."), ("ship it", "ship it.")])
    func addsStop(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "leaves text that already ends, looks like code, or is empty",
        arguments: [
            "hello.", "hello!", "hello?", "hello…", "hello,", "\"hello\"", "get_user(id)",
            "SELECT * FROM user;",
            "let x = [1, 2, 3]", "func main() {}", "",
        ]
    )
    func leavesFinished(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("adds nothing when the text holds a line break and the layout keeps newlines")
    func leavesLayout() {
        let code = TerminalStopPass(policy: .always, layout: .preserveNewlines)
        let draft = Draft(words: ["line", "one", "\n", "line", "two"].map { Draft.Word($0) })
        #expect(code.apply(draft).text == "line one\nline two")
        #expect(code.apply(Draft(text: "ship it")).text == "ship it.")
    }

    @Test("ends the last sentence under a paragraph layout whatever line breaks the text holds")
    func paragraphsEndTheLast() {
        let draft = Draft(words: ["line", "one", "\n", "line", "two"].map { Draft.Word($0) })
        #expect(sut.apply(draft).text == "line one\nline two.")
        let long = Draft(keepingLineBreaks: "One. Two.\n\nThree here")
        #expect(short.apply(long).text == "One. Two.\n\nThree here.")
    }

    @Test(
        "ends each paragraph of three or more words with a full stop, and leaves one that has a mark",
        arguments: [
            (
                "thanks for your note\n\nI've attached the revised quote",
                "thanks for your note.\n\nI've attached the revised quote."
            ),
            ("Thanks\n\nThe second issue", "Thanks\n\nThe second issue."),
            ("Ready?\n\nSee you at five", "Ready?\n\nSee you at five."),
            ("one two\nthree four\n\nfive six seven", "one two\nthree four.\n\nfive six seven."),
        ])
    func paragraphStops(text: String, expected: String) {
        #expect(sut.apply(Draft(keepingLineBreaks: text)).text == expected)
    }

    @Test("gives a list item no stop, at the end or before a blank line")
    func listItems() {
        let list = Draft(keepingLineBreaks: "what's left to pack\n- the tent\n- the first aid kit")
        #expect(sut.apply(list).text == "what's left to pack\n- the tent\n- the first aid kit")
        let after = Draft(keepingLineBreaks: "- the tent and the stove\n\nthat is all we need")
        #expect(sut.apply(after).text == "- the tent and the stove\n\nthat is all we need.")
        let items = Draft(keepingLineBreaks: "- the tent and the stove\n- the first aid kit here")
        #expect(sut.apply(items).text == "- the tent and the stove\n- the first aid kit here")
    }

    @Test("collapses every line break to a space under a single-line layout")
    func singleLine() {
        let cell = TerminalStopPass(policy: .never, layout: .singleLine)
        #expect(cell.apply(Draft(keepingLineBreaks: "line one\nline two.")).text == "line one line two")
        #expect(cell.apply(Draft(keepingLineBreaks: "a\n\n- b\n- c")).text == "a b c")
        let stopped = TerminalStopPass(policy: .always, layout: .singleLine)
        #expect(stopped.apply(Draft(keepingLineBreaks: "line one\nline two")).text == "line one line two.")
    }

    @Test("adds no paragraph stop when the policy is never, and lays out paragraphs by default")
    func neverAndDefault() {
        let paragraphs = TerminalStopPass(policy: .never, layout: .paragraphs)
        #expect(
            paragraphs.apply(Draft(keepingLineBreaks: "one two three\n\nfour five six.")).text
                == "one two three\n\nfour five six")
        #expect(TerminalStopPass().layout == .paragraphs)
    }

    @Test("never adds a stop, and takes back one that was put there")
    func neverAdds() {
        #expect(cleaned("total revenue", by: never) == "total revenue")
        #expect(cleaned("total revenue.", by: never) == "total revenue")
        #expect(cleaned("return x;", by: never) == "return x;")
    }

    @Test(
        "never keeps a question mark, an exclamation mark and an ellipsis",
        arguments: ["ready?", "go!", "wait...", "wait…"])
    func neverKeepsOtherMarks(text: String) {
        #expect(cleaned(text, by: never) == text)
    }

    @Test("a short message has its stop withheld, whoever put it there")
    func shortMessages() {
        #expect(cleaned("on my way", by: short) == "on my way")
        #expect(cleaned("On my way.", by: short) == "On my way")
        #expect(
            cleaned("Are you around? I should be there in ten.", by: short)
                == "Are you around? I should be there in ten")
    }

    @Test("a longer message keeps its stop, and gains one it lacked")
    func longerMessages() {
        #expect(cleaned("One. Two. Three.", by: short) == "One. Two. Three.")
        #expect(cleaned("One. Two. Three", by: short) == "One. Two. Three.")
    }

    @Test(
        "a short message keeps a question mark, an exclamation mark and an ellipsis",
        arguments: ["Ready?", "Go!", "Well…"])
    func shortMessagesKeepOtherMarks(text: String) {
        #expect(cleaned(text, by: short) == text)
    }

    @Test(
        "counts sentences by their marks, with a decimal point and a run of marks not counting",
        arguments: [
            ("", 0), ("   ", 0), ("one", 1), ("one.", 1), ("One. Two", 2), ("One. Two.", 2),
            ("Version 16.2 is out.", 1), ("Really?! Yes.", 2), ("One!  Two?  Three...", 3),
            ("line one\nline two.", 1),
        ]
    )
    func sentenceCount(text: String, expected: Int) {
        #expect(TerminalStopPass.sentenceCount(text) == expected)
    }

    @Test("records the stop against the last word, and nothing against a word it left alone")
    func provenance() {
        let draft = sut.apply(Draft(text: "hello there"))
        #expect(draft.words[1].state == .replaced(by: TerminalStopPass.id, from: "there"))
        let flattened = TerminalStopPass(policy: .never, layout: .singleLine)
            .apply(Draft(keepingLineBreaks: "one\ntwo"))
        #expect(flattened.words[1].state == .removed(by: TerminalStopPass.id))
        let paragraphs = sut.apply(Draft(keepingLineBreaks: "one two three\n\nfour"))
        #expect(paragraphs.words[2].state == .replaced(by: TerminalStopPass.id, from: "three"))
        #expect(short.apply(Draft(text: "on my way")).words[2].state == .kept)
        #expect(
            never.apply(Draft(text: "on my way.")).words[2].state
                == .replaced(by: TerminalStopPass.id, from: "way."))
    }
}
