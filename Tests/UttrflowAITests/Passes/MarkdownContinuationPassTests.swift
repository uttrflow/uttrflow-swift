import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("An item word in a Markdown document continues what is written")
struct MarkdownContinuationPassTests {
    private func written(
        _ spoken: String, after precedingText: String, in documentName: String = "notes.md",
        destination: Destination = .codeEditor
    ) -> String {
        let app = AppContext(documentName: documentName, precedingText: precedingText)
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: destination)
        let formatter = DestinationFormatter.standard(for: destination)
        return CleaningPipeline.standard(for: formatter, situation: situation).run(Draft(text: spoken)).text
    }

    @Test(
        "writes the next mark of the list the caret's line is in",
        arguments: [
            ("next item buy milk", "1. eggs", "\n2. buy milk"),
            ("next item buy milk", "3. eggs", "\n4. buy milk"),
            ("new item buy milk", "9) eggs", "\n10) buy milk"),
            ("next item buy milk", "- eggs", "\n- buy milk"),
            ("next item buy milk", "* eggs", "\n* buy milk"),
            ("next item buy milk", "+ eggs", "\n+ buy milk"),
            ("next item buy milk", "- [ ] eggs", "\n- [ ] buy milk"),
            ("next item buy milk", "- [x] eggs", "\n- [ ] buy milk"),
            ("next item buy milk", "  - eggs", "\n  - buy milk"),
            ("next item buy milk", "    2. eggs", "\n    3. buy milk"),
            ("next item buy milk", "> - eggs", "\n> - buy milk"),
            ("next item buy milk", "Shopping\n\n1. eggs\n2. flour", "\n3. buy milk"),
        ])
    func continuesList(spoken: String, preceding: String, expected: String) {
        #expect(written(spoken, after: preceding) == expected)
    }

    @Test("numbers each item said in one utterance after the one before it")
    func numbersEachItem() {
        #expect(
            written("next item eggs. next item flour. next item butter", after: "1. milk")
                == "\n2. eggs.\n3. Flour.\n4. Butter")
    }

    @Test(
        "writes a heading one level below the last, never past six",
        arguments: [
            ("# Title\n\nSome words", "\n\n## goals"),
            ("## Plan\n\n### Goals\n- a", "\n\n#### Goals"),
            ("###### Deep", "\n\n###### goals"),
            ("Intro text\n\n# Title\n\n", "## Goals"),
            ("", "# Goals"),
        ])
    func writesHeading(preceding: String, expected: String) {
        let text = written("new heading goals", after: preceding)
        #expect(text == expected)
    }

    @Test(
        "leaves the words alone where no list is written",
        arguments: [
            ("next item buy milk", "Some prose here"),
            ("next item buy milk", ""),
            ("next item buy milk", "1. "),
            ("next item buy milk", "```\n- eggs"),
            ("next item buy milk", "~~~sh\n1. eggs"),
        ])
    func leavesWords(spoken: String, preceding: String) {
        #expect(
            !written(spoken, after: preceding).contains("\n2.")
                && !written(spoken, after: preceding).contains("\n-"))
        #expect(written(spoken, after: preceding).lowercased().contains("next item"))
    }

    @Test("reads a mention of an item word as words")
    func mention() {
        #expect(written("I said next item twice", after: "- eggs").lowercased().contains("next item"))
    }

    @Test("does nothing outside a Markdown document")
    func notMarkdown() {
        #expect(
            written("next item buy milk", after: "1. eggs", in: "notes.txt").lowercased().contains(
                "next item"))
    }

    @Test("is idempotent on its own output")
    func idempotent() {
        let pass = MarkdownContinuationPass(position: .at("1. eggs"))
        let once = pass.apply(Draft(text: "next item buy milk"))
        #expect(pass.apply(once).text == once.text)
    }
}
