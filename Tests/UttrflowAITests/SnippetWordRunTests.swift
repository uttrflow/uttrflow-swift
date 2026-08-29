import UttrflowCore
import Testing

@testable import UttrflowAI

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
            // A trailing run has no separator after it to close it, which is the one
            // case a scanner gets wrong.
            ("ends in a word", ["ends", "in", "a", "word"]),
            ("ends in punctuation.", ["ends", "in", "punctuation"]),
            ("v2 of the 3rd draft", ["v2", "of", "the", "3rd", "draft"]),
            // An apostrophe separates, which is what lets the expander see that
            // "address" here is glued to something and refuse to fire.
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

    /// The range is what lets a replacement land on the words and leave the full stop
    /// the tidier added exactly where it was.
    @Test("says where each run sits, so a replacement can be surgical")
    func rangesPointAtTheRun() {
        let text = "My address."
        let runs = text.snippetWordRuns()
        #expect(runs.map { String(text[$0.range]) } == ["My", "address"])
        #expect(text[runs[1].range.upperBound...] == ".")
    }
}
