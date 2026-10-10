import Testing
import UttrflowCore

@testable import UttrflowAI

/// Issue #1955: replacing a selection does not duplicate punctuation or end a continuing clause.
@Suite("Replacing a selection keeps its punctuation single", .bug(id: 1955))
struct SelectionReplacementPunctuationTests {
    private let precedingText = "Please send the report to Alex by "

    @Test(
        "replacing Monday keeps the existing following text",
        arguments: [(".", "Friday"), (" and then…", "Friday")]
    )
    func replacementKeepsFollowingText(_ followingText: String, expected: String) {
        let app = AppContext(
            selectedText: "Monday", precedingText: precedingText, followingText: followingText)
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: .plain)
        let replacement = CleaningPipeline.standard(for: formatter, situation: situation)
            .run(Draft(text: "Friday"))

        #expect(replacement.text == expected)
    }
}
