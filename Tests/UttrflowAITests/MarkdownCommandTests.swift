import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Markdown structure said under the editing key edits the selection, only in a Markdown document")
struct MarkdownCommandTests {
    private func edit(
        _ heard: String, selecting selection: String?, after preceding: String = "",
        in document: String? = "notes.md"
    ) -> String? {
        MarkdownCommand.edit(
            for: heard,
            on: AppContext(documentName: document, selectedText: selection, precedingText: preceding))
    }

    @Test("a span mark wraps the selection and closes where the selection ends, spaces outside the marks")
    func spanMarks() {
        #expect(edit("Bold.", selecting: "ship it ") == "**ship it** ")
        #expect(edit("italics", selecting: "now") == "_now_")
        #expect(edit("inline code", selecting: "make verify") == "`make verify`")
    }

    @Test("a code block fences whole lines and needs the caret at a line start")
    func codeBlock() {
        #expect(edit("code block", selecting: "let a = 1\n") == "```\nlet a = 1\n```\n")
        #expect(edit("code block", selecting: "let a = 1", after: "Run ") == nil)
    }

    @Test("a line mark goes before every non-empty line, and only from a line start")
    func lineMarks() {
        #expect(edit("Heading two.", selecting: "Plan", after: "Intro\n") == "## Plan")
        #expect(edit("heading 1", selecting: nil) == "# ")
        #expect(edit("block quote", selecting: "one\n\ntwo") == "> one\n\n> two")
        #expect(edit("heading one", selecting: "Plan", after: "The ") == nil)
    }

    @Test("a span mark with nothing selected has no span to close, so nothing is written")
    func emptySpan() {
        #expect(edit("bold", selecting: nil) == nil)
        #expect(edit("bold", selecting: "  ") == nil)
    }

    @Test("the same words where Markdown does not render, or as part of other words, are not a command")
    func negativeClass() {
        #expect(edit("bold", selecting: "ship it", in: "Untitled") == nil)
        #expect(edit("bold", selecting: "ship it", in: "main.swift") == nil)
        #expect(edit("bold", selecting: "ship it", in: nil) == nil)
        #expect(edit("make it bold", selecting: "ship it") == nil)
    }
}
