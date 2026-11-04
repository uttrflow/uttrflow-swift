import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("LayoutWordsPass enumerated series")
struct LayoutWordsPassEnumeratedSeriesTests {
    private let sut = LayoutWordsPass()

    @Test(
        "lists a series a counted cue announces when the count matches",
        arguments: [
            (
                "the following three items: milk, eggs, and bread.",
                "the following three items:\n- milk\n- eggs\n- bread."
            ),
            (
                "we need the following three things, milk, eggs and bread",
                "we need the following three things:\n- milk\n- eggs\n- bread"
            ),
            (
                "the following 2 tasks: call the plumber, pay the rent.",
                "the following 2 tasks:\n- call the plumber\n- pay the rent."
            ),
        ]
    )
    func listsCountedSeries(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "leaves a series as prose without a matching counted cue",
        arguments: [
            "pack socks, shirts, and a towel.",
            "the following three items: milk, eggs.",
            "the following three items: milk, eggs, bread, and jam.",
            "the following three items milk eggs and bread.",
            "the following items: milk, eggs, and bread.",
            "over the following three days, we shipped it, fixed it, and tested it.",
            "in the following three items: milk, eggs, and bread.",
            "the following three items: milk, eggs, and a very long item that runs on for words and words.",
            "the following two days: monday, tuesday.",
            "the following three items are milk, eggs and bread.",
            "the following three items: milk, eggs and bread, then we leave.",
            "the following three people came: ann, bob and cy.",
            "we bought milk, eggs, and bread.",
        ]
    )
    func keepsProse(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("lists a series of an irregular plural the cue counts")
    func irregularPlural() {
        let input = "the following three men: ann, bob and cy."
        #expect(cleaned(input, by: sut) == "the following three men:\n- ann\n- bob\n- cy.")
    }

    @Test("tags every list mark it writes as an announced series")
    func tagsMarks() {
        let draft = sut.apply(Draft(text: "the following three items: milk, eggs, and bread."))
        let marks = draft.words.filter(\.isListMark)
        #expect(marks.count == 3)
        #expect(marks.allSatisfy { $0.breakEvidence == .announcedSeries })
    }

    @Test("writes no list where the destination takes none")
    func respectsLayoutPolicy() {
        let input = "the following three items: milk, eggs, and bread."
        #expect(cleaned(input, by: LayoutWordsPass(layout: [.paragraphs])) == input)
    }

    @Test("writes the series on one line in a one-line field")
    func oneLine() {
        let input = "the following three items: milk, eggs, and bread."
        let written = cleaned(input, by: LayoutWordsPass(layout: .singleLine))
        #expect(written == "the following three items, milk, eggs, bread.")
    }

    @Test("writes the list through the shipped pipeline")
    func throughPipeline() {
        let text = CleaningPipeline.standard.run(
            Draft(text: "the following three items: milk, eggs, and bread.")
        ).text
        #expect(text == "The following three items:\n- Milk\n- Eggs\n- Bread")
    }
}
