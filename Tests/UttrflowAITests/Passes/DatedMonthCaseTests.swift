import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A month word that is also a verb or modal, in a date")
struct DatedMonthCaseTests {
    private func cleaned(_ text: String) -> String {
        CleaningPipeline.standard.run(Draft(text: text)).text
    }

    @Test(
        "takes a capital when a day or year follows it",
        arguments: [
            ("see you on march fifth", "See you on March fifth."),
            ("see you on may fifth", "See you on May fifth."),
            ("we meet march fifth", "We meet March fifth."),
            ("the meeting is on march third at two thirty pm", "The meeting is on March third at 2:30 pm."),
            ("see you on march twelfth", "See you on March 12."),
            ("we ship in may 2027", "We ship in May 2027."),
        ])
    func datedMonthIsCapitalised(input: String, expected: String) {
        #expect(cleaned(input) == expected)
    }

    @Test(
        "stays a verb or modal where no date follows",
        arguments: [
            ("we march on friday", "We march on Friday."),
            ("you may go", "You may go."),
            ("it may happen in march", "It may happen in march."),
        ])
    func verbIsUntouched(input: String, expected: String) {
        #expect(cleaned(input) == expected)
    }
}
