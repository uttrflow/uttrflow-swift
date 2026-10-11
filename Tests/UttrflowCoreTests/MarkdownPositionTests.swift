import Testing

@testable import UttrflowCore

@Suite("The Markdown position at the caret")
struct MarkdownPositionTests {
    @Test(
        "reads the next mark of a list item",
        arguments: [
            ("1. one", "2. "), ("7) seven", "8) "), ("- a", "- "), ("* a", "* "), ("+ a", "+ "),
            ("- [ ] a", "- [ ] "), ("- [X] a", "- [ ] "), ("   - a", "   - "), ("> 2. a", "> 3. "),
            ("> > - a", "> > - "),
        ])
    func nextMark(text: String, expected: String) {
        #expect(MarkdownPosition.at(text).continuation() == expected)
    }

    @Test("skips the items already written after the caret's")
    func skipping() {
        #expect(MarkdownPosition.at("4. a").continuation(skipping: 2) == "7. ")
    }

    @Test(
        "gives no continuation where no item has words",
        arguments: [
            "", "prose", "1. ", "- ", "-no space", "1.5 apples", "```\n- a", "~~~\n1. a", "12345678901. a",
        ])
    func none(text: String) {
        #expect(MarkdownPosition.at(text).continuation() == nil)
    }

    @Test("a closed fence no longer holds the caret")
    func closedFence() {
        let position = MarkdownPosition.at("```swift\nlet a = 1\n```\n- a")
        #expect(!position.isInFence)
        #expect(position.continuation() == "- ")
    }

    @Test("names the language of the open fence")
    func fenceLanguage() {
        #expect(MarkdownPosition.at("text\n```Swift\nlet a").fenceLanguage == "swift")
        #expect(MarkdownPosition.at("~~~\nx").fenceLanguage == "")
        #expect(MarkdownPosition.at("````\n```\nx").isInFence)
    }

    @Test("reads the last heading outside fences")
    func headings() {
        #expect(MarkdownPosition.at("# A\n\n## B\ntext").lastHeadingLevel == 2)
        #expect(MarkdownPosition.at("# A\n```\n### not\n").lastHeadingLevel == 1)
        #expect(MarkdownPosition.at("#nospace").lastHeadingLevel == nil)
        #expect(MarkdownPosition.at("####### seven").lastHeadingLevel == nil)
        #expect(
            MarkdownPosition.at("prose").nextHeading == nil || MarkdownPosition.at("prose").nextHeading == "#"
        )
        #expect(MarkdownPosition.at("###### a").nextHeading == "######")
        #expect(MarkdownPosition.at("```\n# a").nextHeading == nil)
    }

    @Test("a missing field says nothing")
    func unknown() {
        #expect(MarkdownPosition.at(nil).continuation() == nil)
        #expect(MarkdownPosition.at(nil).nextHeading == nil)
    }
}
