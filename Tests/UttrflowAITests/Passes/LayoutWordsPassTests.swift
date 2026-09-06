import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("LayoutWordsPass")
struct LayoutWordsPassTests {
    private let sut = LayoutWordsPass()

    @Test(
        "turns a layout word between other words into layout",
        arguments: [
            ("first line new line second line", "first line\nsecond line"),
            ("thanks new paragraph the second issue", "thanks\n\nthe second issue"),
            ("thanks blank line the second issue", "thanks\n\nthe second issue"),
            ("we need bullet point milk bullet point eggs", "we need\n- milk\n- eggs"),
            ("first next point second", "first\n- second"),
        ]
    )
    func laysOut(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "leaves a layout word that is mentioned, first, or last",
        arguments: [
            "add a new line here",
            "the next point is",
            "new line",
            "hello new line",
            "new line hello",
            "my next point of order",
            "three bullet points",
        ]
    )
    func leavesMentions(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("records the layout mark as a replacement and the second word as removed")
    func provenance() {
        let draft = sut.apply(Draft(text: "one new line two"))
        #expect(draft.words[1].state == .replaced(by: LayoutWordsPass.id, from: "new"))
        #expect(draft.words[2].state == .removed(by: LayoutWordsPass.id))
        #expect(draft.words[1].isLayoutMark)
    }
}
