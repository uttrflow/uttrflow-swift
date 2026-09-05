import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("TerminalStopPass")
struct TerminalStopPassTests {
    private let sut = TerminalStopPass()

    @Test(
        "finishes a sentence that has no ending", arguments: [("hello there", "hello there."), ("42", "42.")])
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

    @Test("adds nothing when the text holds a line break")
    func leavesLayout() {
        let draft = Draft(words: ["line", "one", "\n", "line", "two"].map { Draft.Word($0) })
        #expect(sut.apply(draft).text == "line one\nline two")
    }

    @Test("adds nothing under the never policy")
    func never() {
        #expect(cleaned("hello there", by: TerminalStopPass(policy: .never)) == "hello there")
    }

    @Test("records the stop against the last word")
    func provenance() {
        let draft = sut.apply(Draft(text: "hello there"))
        #expect(draft.words[1].state == .replaced(by: TerminalStopPass.id, from: "there"))
    }
}
