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
            ("we need number twenty one milk number twenty two eggs", "we need\n21. milk\n22. eggs"),
            (
                "then number two call the landlord number three pay the rent",
                "then\n2. call the landlord\n3. pay the rent"
            ),
            ("we need number 1 milk number 2 eggs", "we need\n1. milk\n2. eggs"),
        ]
    )
    func numbersItems(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// Issue 254: with no lookback to ask, a phrase opening its sentence is an item only if the speaker set it off.
    @Test(
        "reads a phrase opening its sentence as layout only when a mark sets it off",
        arguments: [
            ("the build failed. number one is broken", "the build failed. number one is broken"),
            ("here is the plan. number one, fix the build", "here is the plan.\n1. fix the build"),
            ("number one, fix the build", "1. fix the build"),
            ("bullet point, the milk", "- the milk"),
            ("we shipped. bullet point, the milk", "we shipped.\n- the milk"),
            // A break at the head of the text has nothing to break from, so the words stay.
            ("new line, hello there", "new line, hello there"),
        ]
    )
    func readsTheSentenceNotTheText(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// One spoken phrase cannot straddle a sentence end, so neither the phrase nor the item number reaches past one.
    @Test(
        "reads neither a layout phrase nor an item number across a sentence end",
        arguments: [
            (
                "we need number nineteen milk number twenty. One more of them",
                "we need\n19. milk\n20. One more of them"
            ),
            ("I bought something new. Line up here", "I bought something new. Line up here"),
            ("show me what is next. Point two is wrong", "show me what is next. Point two is wrong"),
        ]
    )
    func staysInsideTheSentence(input: String, expected: String) {
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

    /// Issue 238: a numbered item inside its sentence is laid out only when an item numbered next to it is said too.
    @Test(
        "leaves a lone number inside its sentence as the designator it is",
        arguments: [
            "ring number 5 now", "call number 5 please", "check number 7 again",
            "shopping list number three call the bank", "we need number twenty one more of them",
            "room number 5 is free and so is room number 7", "take bus number twelve to the station",
            "check number 9223372036854775807 again",
        ]
    )
    func leavesALoneDesignator(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "keeps boundary and unparseable numbers as ordinary text",
        arguments: [
            "check number 9223372036854775806 again",
            "check number 0 again",
            "check number 9223372036854775808 again",
        ]
    )
    func keepsBoundaryNumbers(input: String) {
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
        let draft = sut.apply(Draft(text: "milk number twenty one eggs number twenty two bread"))
        #expect(draft.words[1].state == .replaced(by: LayoutWordsPass.id, from: "number"))
        #expect(draft.words[2].state == .removed(by: LayoutWordsPass.id))
        #expect(draft.words[3].state == .removed(by: LayoutWordsPass.id))
        #expect(draft.words[1].isLayoutMark && draft.words[1].isListMark)
    }
}
