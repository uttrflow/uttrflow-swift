import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("An annotation word that opens a comment")
struct CommentMarkerPassTests {
    private func written(
        _ spoken: String, after precedingText: String, in documentName: String = "Example.swift",
        destination: Destination = .codeEditor
    ) -> String {
        let app = AppContext(documentName: documentName, precedingText: precedingText)
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: destination)
        let formatter = DestinationFormatter.standard(for: destination)
        return CleaningPipeline.standard(for: formatter, situation: situation).run(Draft(text: spoken)).text
    }

    private func opener(_ spoken: String, after precedingText: String, in documentName: String) -> String? {
        written(spoken, after: precedingText, in: documentName).split(separator: " ").first.map(String.init)
    }

    @Test(
        "writes the marker as the lexicon writes it, after every comment opener",
        arguments: [
            ("todo colon at sam replace the polling loop", "// ", "Example.swift", "TODO:"),
            ("to do colon replace the polling loop", "// ", "Example.swift", "TODO:"),
            ("fixme colon handle the empty case", "    // ", "Example.swift", "FIXME:"),
            ("fix me colon handle the empty case", "let x = 1 // ", "Example.swift", "FIXME:"),
            ("note colon this runs twice", "/* ", "Example.swift", "NOTE:"),
            ("hack colon skip the cache", "/*\n * ", "Example.swift", "HACK:"),
            ("x x x colon remove before release", "/*\n", "Example.swift", "XXX:"),
            ("todo colon read the size first", "# ", "example.py", "TODO:"),
            ("fixme colon the loop never ends", "    # ", "example.py", "FIXME:"),
            ("note colon the docstring stays", "\"\"\"\n", "example.py", "NOTE:"),
            ("todo colon index this column", "-- ", "example.sql", "TODO:"),
            ("hack colon the join is slow", "/* ", "example.sql", "HACK:"),
            ("todo colon free the buffer", "-- ", "example.lua", "TODO:"),
            ("fixme colon set the width", "/* ", "example.css", "FIXME:"),
            ("note colon kept for old readers", "<!-- ", "example.html", "NOTE:"),
        ])
    func writesMarker(spoken: String, precedingText: String, documentName: String, expected: String) {
        #expect(opener(spoken, after: precedingText, in: documentName) == expected)
    }

    @Test("keeps every spoken word after the marker")
    func keepsOwner() {
        let text = written("todo colon at sam replace the polling loop", after: "// ")
        #expect(text.hasPrefix("TODO: "))
        #expect(text.contains("sam replace the polling loop"))
    }

    @Test(
        "leaves the word alone where it is not a comment's marker",
        arguments: [
            ("the todo list is long", "// "),
            ("note the changes", "// "),
            ("fix me a coffee", "# "),
            ("then todo colon later", "// "),
            ("todo colon later", "// keep this, "),
            ("todo colon later", "let x = "),
        ])
    func leavesProse(spoken: String, precedingText: String) {
        let opener = written(spoken, after: precedingText).split(separator: " ")
        #expect(!opener.contains { ["TODO", "TODO:", "FIXME", "FIXME:", "NOTE", "NOTE:"].contains($0) })
    }

    @Test("leaves the word alone outside a code editor", arguments: [Destination.plain, .document, .email])
    func leavesOtherDestinations(destination: Destination) {
        let text = written("todo colon call the bank", after: "// ", destination: destination)
        #expect(!text.hasPrefix("TODO"))
    }
}
