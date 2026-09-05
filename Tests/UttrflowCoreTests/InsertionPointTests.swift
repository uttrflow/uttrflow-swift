import Testing

@testable import UttrflowCore

@Suite("InsertionPoint")
struct InsertionPointTests {
    @Test("does not know where the caret is when the field would not say")
    func unknownWithoutText() {
        #expect(InsertionPoint.sentenceState(before: nil) == .unknown)
        #expect(InsertionPoint.unknown.sentenceState == .unknown)
    }

    @Test(
        "an empty field, or one holding only spaces, is the start of the text",
        arguments: ["", "   ", " \t "])
    func startOfText(preceding: String) {
        #expect(InsertionPoint.sentenceState(before: preceding) == .startOfText)
    }

    @Test(
        "a sentence end or a line break before the caret starts a sentence",
        arguments: [
            "Ship it.", "Ship it. ", "Really?", "Go!\t", "first line\n", "first line\n   ", "Done.\n\n",
            "\n\n",
        ]
    )
    func startOfSentence(preceding: String) {
        #expect(InsertionPoint.sentenceState(before: preceding) == .startOfSentence)
    }

    @Test(
        "any other last mark leaves the caret mid-sentence",
        arguments: [
            "The build failed because", "The build failed because ", "milk, eggs,", "wait…",
            "He said \"go.\"",
        ]
    )
    func midSentence(preceding: String) {
        #expect(InsertionPoint.sentenceState(before: preceding) == .midSentence)
    }

    @Test("keeps both sides of the caret exactly as given")
    func keepsText() {
        let point = InsertionPoint(precedingText: "before ", followingText: " after")
        #expect(point.precedingText == "before ")
        #expect(point.followingText == " after")
        #expect(point.sentenceState == .midSentence)
    }

    @Test("bounds what a reader keeps either side of the caret")
    func limits() {
        #expect(InsertionPoint.precedingLimit == 300)
        #expect(InsertionPoint.followingLimit == 100)
    }
}
