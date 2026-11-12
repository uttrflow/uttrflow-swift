import Testing
import UttrflowCore

@testable import UttrflowAI

/// The two ends of a spoken range take one form, so a range never reads half in words and half in digits.
@Suite("NumberFormsPass ranges")
struct NumberRangeFormTests {
    @Test(
        "writes both ends of a range in digits when either end would be",
        arguments: [
            ("pages five to ten", "pages 5 to 10"),
            ("between five and fifteen people", "between 5 and 15 people"),
            ("from nine to eleven am", "from 9 to 11 am"),
            ("a two hour meeting from two to four pm", "a two hour meeting from 2 to 4 pm"),
            ("chapters two through twelve", "chapters 2 through 12"),
        ]
    )
    func mixedRange(input: String, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass()) == expected)
    }

    @Test(
        "writes the numbers said straight after a plural label as its singular label does",
        arguments: [
            ("see pages four and seven", "see pages 4 and 7"),
            ("read chapters three to five", "read chapters 3 to 5"),
            ("follow steps one to three", "follow steps 1 to 3"),
            ("sections two and four", "sections 2 and 4"),
            ("lines six to nine", "lines 6 to 9"),
            ("rooms two and three", "rooms 2 and 3"),
        ]
    )
    func pluralLabels(input: String, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass()) == expected)
    }

    @Test(
        "keeps a range of small counts in words",
        arguments: [
            ("three to five days", "three to five days"),
            ("a one to one meeting", "a one to one meeting"),
            ("two or three people", "two or three people"),
            ("the pages of two books", "the pages of two books"),
            ("three pages and two steps", "three pages and two steps"),
        ]
    )
    func smallCounts(input: String, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass()) == expected)
    }
}
