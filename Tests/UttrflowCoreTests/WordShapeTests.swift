import Testing

@testable import UttrflowCore

@Suite("WordShape")
struct WordShapeTests {
    @Test(
        "puts a mark on the end of a word, replacing a clause mark already there",
        arguments: [
            ("today", "?", "today?"),
            ("today,", "?", "today?"),
            ("today.", "!", "today!"),
            ("today", "\"", "today\""),
            ("today\"", ".", "today\"."),
            ("today", "\u{2014}", "today \u{2014}"),
        ]
    )
    func marked(text: String, mark: String, expected: String) {
        #expect(WordShape.marked(text, with: mark) == expected)
    }

    @Test(
        "folds several marks on in turn, under the same rule",
        arguments: [
            ("today", "?\"", "today?\""),
            ("today,", "?", "today?"),
            // An ellipsis is three clause marks, so it ends as the one mark they collapse to.
            ("today", "...", "today."),
            ("today", "", "today"),
        ]
    )
    func markedWithSeveral(text: String, marks: String, expected: String) {
        #expect(WordShape.marked(text, withAll: marks) == expected)
    }
}
