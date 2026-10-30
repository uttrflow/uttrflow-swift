import Foundation
import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowPipeline

/// A fixed list of snippets expands as the stored ones do, and only where each applies.
@Suite("Listed snippets")
struct ListedSnippetsTests {
    static let sign = Snippet(
        trigger: "sign off block", expansion: "Best wishes,\nSam Example",
        created: Date(timeIntervalSince1970: 0))
    static let scoped = Snippet(
        trigger: "my desk", expansion: "Desk 4", created: Date(timeIntervalSince1970: 0),
        applications: ["com.example.notes"])

    @Test("expands a trigger and records the snippet that fired")
    func expandsAndRecords() async {
        let expanded = await ListedSnippets([Self.sign]).expand("Thanks. Sign off block", in: nil)
        #expect(expanded.text.contains("Best wishes,\nSam Example"))
        #expect(expanded.snippets.map(\.snippetID) == [Self.sign.id])
    }

    @Test("fires a scoped snippet only in its application")
    func keepsItsScope() async {
        let listed = ListedSnippets([Self.scoped])
        #expect(await listed.expand("at my desk", in: "com.example.mail").text == "at my desk")
        #expect(await listed.expand("at my desk", in: "com.example.notes").text.contains("Desk 4"))
    }
}
