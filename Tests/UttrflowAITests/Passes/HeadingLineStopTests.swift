import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("The final stop on a Markdown heading line")
struct HeadingLineStopTests {
    private func written(
        _ text: String, after preceding: String?, in destination: Destination = .document
    ) -> String {
        let pass = TerminalStopPass(
            policy: .always, insertionPoint: InsertionPoint(precedingText: preceding),
            destination: destination)
        return pass.apply(Draft(text: text)).text
    }

    @Test(
        "withholds the stop after a heading marker and leaves the words alone",
        arguments: [
            ("meeting notes", "# ", "meeting notes"),
            ("Meeting notes", "## ", "Meeting notes"),
            ("project plan", "intro text\n\n### ", "project plan"),
            ("what is next?", "# ", "what is next?"),
            ("the first of many", "  ## ", "the first of many"),
        ])
    func headingLine(text: String, preceding: String, expected: String) {
        #expect(written(text, after: preceding) == expected)
    }

    @Test(
        "keeps the stop on an ordinary line, a tag, a long marker and another destination",
        arguments: [
            ("meeting notes", "", "meeting notes."),
            ("meeting notes", "# title\n\n", "meeting notes."),
            ("meeting notes", "#hashtag ", "meeting notes."),
            ("meeting notes", "####### ", "meeting notes."),
            ("meeting notes", "A line with # inside ", "meeting notes."),
        ])
    func ordinaryLine(text: String, preceding: String, expected: String) {
        #expect(written(text, after: preceding) == expected)
    }

    @Test("keeps the stop in a destination that is not a document")
    func otherDestination() {
        #expect(written("meeting notes", after: "# ", in: .plain) == "meeting notes.")
    }
}
