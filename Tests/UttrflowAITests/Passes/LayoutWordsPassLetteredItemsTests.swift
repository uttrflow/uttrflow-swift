import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("LayoutWordsPass lettered and roman items")
struct LayoutWordsPassLetteredItemsTests {
    private let sut = LayoutWordsPass()

    @Test(
        "writes labels said in order as bracketed lines",
        arguments: [
            (
                "the supplier shall item a deliver within thirty days item b replace any damaged goods item c keep records for six years",
                "the supplier shall\n(a) deliver within thirty days\n(b) replace any damaged goods\n(c) keep records for six years"
            ),
            ("item a deliver the goods item b pay the invoice", "(a) deliver the goods\n(b) pay the invoice"),
            (
                "the tenant must limb i pay rent limb ii keep the unit clean limb iii report damage",
                "the tenant must\n(i) pay rent\n(ii) keep the unit clean\n(iii) report damage"
            ),
            ("paragraph a notice period paragraph b payment terms", "(a) notice period\n(b) payment terms"),
            ("sub clause a first duty sub clause b second duty", "(a) first duty\n(b) second duty"),
            ("subclause a first duty subclause b second duty", "(a) first duty\n(b) second duty"),
            (
                "the policy covers item a fire, item b theft, item c flood",
                "the policy covers\n(a) fire\n(b) theft\n(c) flood"
            ),
            ("clause a scope clause b term", "(a) scope\n(b) term"),
            (
                "the board agreed item a to hire item b to train and item c to review",
                "the board agreed\n(a) to hire\n(b) to train and\n(c) to review"
            ),
            ("Item A deliver Item B replace", "(a) deliver\n(b) replace"),
            (
                "minutes item i approve the agenda item ii note the budget item iii close the meeting",
                "minutes\n(i) approve the agenda\n(ii) note the budget\n(iii) close the meeting"
            ),
            (
                "item a deliver item b replace item c keep item d report",
                "(a) deliver\n(b) replace\n(c) keep\n(d) report"
            ),
            (
                "limb i first limb ii second limb iii third limb iv fourth",
                "(i) first\n(ii) second\n(iii) third\n(iv) fourth"
            ),
        ]
    )
    func writesLabels(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps the words where the labels are not a list",
        arguments: [
            "item a is late and item b is early",
            "plan a and plan b",
            "part i of the book",
            "we shipped item a and item b yesterday",
            "item a was sent",
            "the item a customer buys and the item b they return",
            "item b replace item c keep",
            "option a or option b",
            "item a deliver",
            "send item a then item b today",
        ]
    )
    func keepsWords(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("keeps the words where no list is laid out")
    func keepsWordsWithoutLists() {
        let input = "item a deliver item b replace"
        #expect(cleaned(input, by: LayoutWordsPass(layout: .paragraphs)) == input)
    }
}
