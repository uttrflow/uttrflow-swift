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

    @Test(
        "gives the near end the far end's scale when the recogniser wrote the range in digits",
        .bug(id: 8110),
        arguments: [
            ("the price went from 20 to 30,000", "the price went from 20,000 to 30,000"),
            ("between 3 and 4,000 people", "between 3,000 and 4,000 people"),
            ("5 or 6,000,000 users", "5,000,000 or 6,000,000 users"),
            ("twenty to 30,000", "20,000 to 30,000"),
            ("20 to thirty thousand", "20,000 to 30,000"),
        ]
    )
    func sharesAWrittenScaleAcrossARange(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "leaves a written range alone when the near end is not smaller or the far end is not whole groups",
        .bug(id: 8110),
        arguments: [
            "from 40 to 30,000", "from 30 to 30,000", "from 20 to 31,500", "from 20 to 30,000.5",
            "from 20,000 to 30,000", "from 120 to 300,000", "3 and 4,000 people", "from 20 to 100,000",
        ]
    )
    func keepsAWrittenRangeThatIsNotShared(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "the integrity audit allows the near end the range rule writes, and no other change to it",
        .bug(id: 8110))
    func integrityAuditAllowsOnlyTheRange() {
        let ranged = sut.apply(Draft(text: "from 20 to 30,000 people"))
        #expect(IntegrityAudit.violations(in: ranged, grants: [:]).isEmpty)
        var stray = Draft(text: "from 20 people")
        stray.replace(at: 1, with: "20,000", by: NumberFormsPass.id)
        #expect(IntegrityAudit.violations(in: stray, grants: [:]).map(\.heard) == ["20"])
    }
}
