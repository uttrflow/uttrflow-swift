import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("NumberFormsPass counting")
struct NumberFormsPassCountingTests {
    private let sut = NumberFormsPass()

    @Test(
        "writes no clock time out of the last two numbers of a count",
        arguments: [
            ("ten eleven twelve thirteen", "10 11 12 13"),
            ("nine ten eleven twelve", "nine ten 11 12"),
            (
                "count one two three four five six seven eight nine ten",
                "count one two three four five six seven eight nine ten"
            ),
        ]
    )
    func aCountIsNotATime(input: String, expected: String) {
        let written = cleaned(input, by: sut)
        #expect(!written.contains(":"))
        #expect(written == expected)
    }

    @Test(
        "still reads two numbers that end a sentence as a time",
        arguments: [
            ("the train leaves at twelve thirteen", "the train leaves at 12:13"),
            ("it was ten fifteen", "it was 10:15"),
            ("we met at nine ten", "we met at 9:10"),
        ]
    )
    func twoNumbersAreStillATime(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }
}
