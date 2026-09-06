import UttrflowCore
import Testing

@testable import UttrflowAI

/// The word runs the expander matches against.
@Suite("Splitting a transcript into the words that were said")
struct SnippetWordRunTests {
    @Test(
        "keeps runs of letters and digits, and nothing else",
        arguments: [
            ("my address", ["my", "address"]),
            // Whatever the tidier added changes the separators, never the runs.
            ("My address.", ["My", "address"]),
            ("Right, my address, please!", ["Right", "my", "address", "please"]),
            ("  spaced  out  ", ["spaced", "out"]),
            // A trailing run has no separator to close it, the one case a scanner gets wrong.
            ("ends in a word", ["ends", "in", "a", "word"]),
            ("ends in punctuation.", ["ends", "in", "punctuation"]),
            ("v2 of the 3rd draft", ["v2", "of", "the", "3rd", "draft"]),
            // An apostrophe separates, so the expander can see "address" here is glued and refuse to fire.
            ("address's", ["address", "s"]),
            ("don't", ["don", "t"]),
            ("pre-approve", ["pre", "approve"]),
            ("", []),
            ("...!!!", []),
        ]
    )
    func runs(input: String, expected: [String]) {
        #expect(input.snippetWordRuns().map(\.text) == expected)
    }

    /// The range lets a replacement land on the words and leave the tidier's full stop in place.
    @Test("says where each run sits, so a replacement can be surgical")
    func rangesPointAtTheRun() {
        let text = "My address."
        let runs = text.snippetWordRuns()
        #expect(runs.map { String(text[$0.range]) } == ["My", "address"])
        #expect(text[runs[1].range.upperBound...] == ".")
    }
}
