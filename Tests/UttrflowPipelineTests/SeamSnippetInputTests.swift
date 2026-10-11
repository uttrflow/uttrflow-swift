import Testing

@testable import UttrflowPipeline

@Suite("Seam stops around a snippet expansion")
struct SeamSnippetInputTests {
    private let input = SeamSnippetInput(
        text: "W1 X. W2 X. W3 X", removableStops: [4, 10], source: "W1 X. W2 X. W3 X")

    /// Spoken words with a seam stop after each word listed in `seams`.
    private static let sources: [(words: [String], seams: [Int])] = [
        (["say", "omw", "then", "brb", "ok"], [1, 3]),
        (["go", "brb", "see", "you", "later"], [1, 3]),
        (["we", "left", "it", "rained", "home"], [1, 3]),
    ]

    /// What a snippet writes in place of one word: shorter, as long and longer, in one word or several.
    private static let replacements = [
        "k", "on", "xyz", "wonderful", "be right back", "on my way soon", "at the station by noon",
    ]

    @Test("an expansion that changed nothing leaves the seam stops where they were")
    func unchangedExpansionKeepsStops() {
        let unchanged = ExpandedTranscript.unchanged(input.removingSeamStops())
        #expect(input.restoringUnconsumedStops(in: unchanged).text == "W1 X. W2 X. W3 X")
    }

    @Test("a stop whose seam is still a gap after the expansion comes back in place")
    func gapKeepsItsStop() {
        let expanded = ExpandedTranscript(text: "W1 X W2 X W3 Y", snippets: [])
        #expect(input.restoringUnconsumedStops(in: expanded).text == "W1 X. W2 X. W3 Y")
    }

    @Test("a snippet's caret moves with the stops restored before it")
    func caretFollowsRestoredStops() {
        let expanded = ExpandedTranscript(text: "W1 X W2 X W3 Y", snippets: [], caret: 6)
        let restored = input.restoringUnconsumedStops(in: expanded)
        #expect(restored.text == "W1 X. W2 X. W3 Y")
        #expect(restored.caret == "W1 X. W".utf16.count)
    }

    @Test("a snippet of any length keeps every seam stop whose words on both sides it left alone")
    func everyReplacementKeepsTheUntouchedSeams() {
        var wrong: [String] = []
        for (words, seams) in Self.sources {
            let input = Self.input(words, seams: seams)
            for replaced in words.indices {
                for replacement in Self.replacements {
                    var written = words
                    written[replaced] = replacement
                    let expected = Self.stopped(written, after: seams.filter { $0 != replaced })
                    let expanded = ExpandedTranscript(text: written.joined(separator: " "))
                    let restored = input.restoringUnconsumedStops(in: expanded).text
                    if restored != expected { wrong.append("\(expected) -> \(restored)") }
                }
            }
        }
        #expect(wrong == [])
    }

    @Test("a caret after a longer snippet moves past the seam stops restored before it")
    func caretFollowsStopsAfterALongerSnippet() {
        let input = Self.input(["say", "omw", "then", "brb", "ok"], seams: [1, 3])
        let text = "say omw be right back brb ok"
        let expanded = ExpandedTranscript(text: text, caret: "say omw be right back brb o".utf16.count)
        let restored = input.restoringUnconsumedStops(in: expanded)
        #expect(restored.text == "say omw. be right back brb. ok")
        #expect(restored.caret == "say omw. be right back brb. o".utf16.count)
    }

    /// The seam input for `words` as the joiner writes them, a stop after each seam word.
    private static func input(_ words: [String], seams: [Int]) -> SeamSnippetInput {
        let source = stopped(words, after: seams)
        let stops = seams.map { seam in
            words[...seam].joined(separator: " ").count + seams.count { $0 < seam }
        }
        return SeamSnippetInput(text: source, removableStops: stops, source: source)
    }

    /// `words` joined by spaces with a full stop after each word listed in `seams`.
    private static func stopped(_ words: [String], after seams: [Int]) -> String {
        words.enumerated().map { seams.contains($0.offset) ? $0.element + "." : $0.element }
            .joined(separator: " ")
    }
}
