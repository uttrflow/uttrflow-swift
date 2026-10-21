import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("NumberFormsPass grouped decimal")
struct NumberFormsPassGroupedDecimalTests {
    private let sut = NumberFormsPass()

    @Test(
        "writes a decimal the recogniser grouped by thousands as the whole number it stands for",
        arguments: [
            ("the budget is roughly £2.5,000, split across three departments",
             "the budget is roughly £2,500, split across three departments"),
            ("it cost $2.5,000 in total", "it cost $2,500 in total"),
            ("about 12.25,000 people came", "about 12,250 people came"),
            ("a total of 1.5,000,000 pounds", "a total of 1,500,000 pounds"),
            ("it was 0.5,000 metres", "it was 500 metres"),
        ]
    )
    func scalesTheDecimal(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "leaves a numeral that is not a decimal times its groups as it was",
        arguments: [
            "it cost £2,500 in total",
            "the ratio is 2.5 to 1",
            "about 3.141,592 of them",
            "they owed 2.5,100 pounds",
            "it was 2.5555,000 pounds",
        ]
    )
    func keepsOtherNumerals(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }
}
