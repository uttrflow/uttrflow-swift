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
        "numbers the items a spoken number opens",
        arguments: [
            ("we need number one milk number two eggs", "we need\n1. milk\n2. eggs"),
            ("shopping list number three call the bank", "shopping list\n3. call the bank"),
            ("we need number twenty one more of them", "we need\n21. more of them"),
            ("we need number 1 milk number 2 eggs", "we need\n1. milk\n2. eggs"),
        ]
    )
    func numbersItems(input: String, expected: String) {
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
            "the number one problem is latency",
            "my number one priority is shipping",
            "number one buy the milk",
            "and that is number two",
        ]
    )
    func leavesMentions(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "leaves a number word that opens no item",
        arguments: [
            "run number zero was the baseline",
            "watch number crunching happen here",
        ]
    )
    func leavesNonItems(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("records the layout mark as a replacement and the second word as removed")
    func provenance() {
        let draft = sut.apply(Draft(text: "one new line two"))
        #expect(draft.words[1].state == .replaced(by: LayoutWordsPass.id, from: "new"))
        #expect(draft.words[2].state == .removed(by: LayoutWordsPass.id))
        #expect(draft.words[1].isLayoutMark)
    }

    @Test("records the item mark as a replacement of number and removes every word of the number said")
    func numberingProvenance() {
        let draft = sut.apply(Draft(text: "milk number twenty one eggs"))
        #expect(draft.words[1].state == .replaced(by: LayoutWordsPass.id, from: "number"))
        #expect(draft.words[2].state == .removed(by: LayoutWordsPass.id))
        #expect(draft.words[3].state == .removed(by: LayoutWordsPass.id))
        #expect(draft.words[1].isLayoutMark && draft.words[1].isListMark)
    }
}
