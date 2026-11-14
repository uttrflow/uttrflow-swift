import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A spoken \"oh\" after \"point\" and \"number zero\" in the shipped pipeline")
struct PointOhAndNumberZeroTests {
    @Test(
        "reads \"oh\" after \"point\" as the digit zero of a decimal",
        arguments: [
            ("three point oh five", "3.05"),
            ("version three point oh", "Version 3.0."),
            ("set it to point oh five percent", "Set it to 0.05%."),
        ])
    func pointOh(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    @Test(
        "leaves a \"point\" with no number beside it as a word",
        arguments: [
            ("the point is", "The point is"),
            ("3 point", "3 point."),
            ("point five", "Point five."),
        ])
    func loosePoint(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    @Test(
        "writes \"number zero\" as the number 0 and never starts a list from it",
        arguments: [
            ("patient number zero", "Patient number 0."),
            (
                "number zero is the first item and number one is next",
                "Number 0 is the first item and number 1 is next."
            ),
        ])
    func numberZero(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }
}
