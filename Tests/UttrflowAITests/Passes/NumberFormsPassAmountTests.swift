import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("NumberFormsPass amounts")
struct NumberFormsPassAmountTests {
    private let sut = NumberFormsPass()

    @Test(
        "writes an amount before a currency word as the symbol and the numeral",
        arguments: [
            ("it cost five dollars", "it cost $5"),
            ("it cost one dollar", "it cost $1"),
            ("pay fifty rupees today", "pay ₹50 today"),
            ("two dollars fifty", "$2.50"),
            ("nine thousand rupees, please", "₹9,000, please"),
            ("ten euros", "€10"),
            ("give me five pounds of flour", "give me 5 pounds of flour"),
            ("it cost five dollars.", "it cost $5."),
            ("a dollar short", "a dollar short"),
            ("between five hundred and six hundred dollars", "between $500 and $600"),
            ("ten to twenty euros", "€10 to €20"),
        ]
    )
    func currencySymbols(input: String, expected: String) {
        let sut = NumberFormsPass(currencySymbols: true)
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "reads a hundred and a tail as one number and keeps a bare hundred or million a word",
        arguments: [
            ("a hundred and fifty users", "150 users"),
            ("about a hundred and fifty users", "about 150 users"),
            ("roughly a hundred and fifteen", "roughly 115"),
            ("it cost a hundred and twenty dollars", "it cost $120"),
            ("a hundred users", "a hundred users"),
            ("a million users", "a million users"),
            ("hundreds of people", "hundreds of people"),
            ("thousands of users", "thousands of users"),
            ("a couple of hundred users", "a couple of hundred users"),
            ("we counted a hundred and twenty. one user left", "we counted 120. one user left"),
        ]
    )
    func hundredWithATail(input: String, expected: String) {
        let sut = NumberFormsPass(currencySymbols: true)
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps the magnitude word of a coefficient under a thousand and writes a sum of groups in full",
        arguments: [
            ("five million", "5 million"),
            ("two point five million", "2.5 million"),
            ("three million two hundred thousand", "3,200,000"),
            ("two hundred and fifty million", "250 million"),
            ("we raised five million dollars", "we raised $5 million"),
            ("a million users", "a million users"),
            ("five million to six million dollars", "$5 million to $6 million"),
        ]
    )
    func magnitudeForms(input: String, expected: String) {
        let sut = NumberFormsPass(currencySymbols: true)
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("leaves the currency word as a word where symbols are not asked for")
    func currencyWordKept() {
        #expect(cleaned("it cost five dollars", by: sut) == "it cost 5 dollars")
    }
}
