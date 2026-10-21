import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("NumberFormsPass shared scale")
struct NumberFormsPassSharedScaleTests {
    private let sut = NumberFormsPass()

    @Test(
        "gives both ends of a range the one scale said after it",
        arguments: [
            ("two to three thousand people", "2000 to 3000 people"),
            ("four or five thousand dollars", "4,000 or 5,000 dollars"),
            ("five or six hundred", "500 or 600"),
            ("three or four hundred", "300 or 400"),
            ("ten to twelve million", "10,000,000 to 12,000,000"),
            ("between two and three thousand", "between 2000 and 3000"),
            ("about two or three hundred users", "about 200 or 300 users"),
            ("one to two hundred", "100 to 200"),
        ]
    )
    func sharesAScaleAcrossARange(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "leaves a range alone when each end has its scale, or the first end is not smaller",
        arguments: [
            ("two hundred to three hundred people", "200 to 300 people"),
            ("five hundred or six hundred", "500 or 600"),
            ("two thousand to three thousand", "2000 to 3000"),
            ("ten to two thousand", "10 to 2000"),
            ("three to two thousand", "3 to 2000"),
            ("two and three thousand", "2 and 3000"),
        ]
    )
    func keepsAScaleThatBelongsToOneEnd(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }
}
