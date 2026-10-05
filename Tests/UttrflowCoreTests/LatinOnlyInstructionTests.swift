import Foundation
import Testing
import UttrflowCore

@Suite("The Latin-only instruction")
struct LatinOnlyInstructionTests {
    @Test("is the wording Docs/latin-output.md quotes, so the page and every prompt say one thing")
    func matchesTheDocsPage() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let page = try String(
            contentsOf: root.appendingPathComponent("Docs/latin-output.md"), encoding: .utf8)
        #expect(page.contains("> \(LatinOnlyInstruction.text)\n"))
    }

    @Test("names the script, the romanised Hindi and the ban on translating")
    func statesTheWholeRule() {
        #expect(LatinOnlyInstruction.text.contains("Latin alphabet"))
        #expect(LatinOnlyInstruction.text.contains("romanised Hinglish"))
        #expect(LatinOnlyInstruction.text.contains("Never write Devanagari"))
        #expect(LatinOnlyInstruction.text.contains("never translate"))
    }
}
