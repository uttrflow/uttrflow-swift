import Foundation
import Testing
import UttrflowCore

@Suite("Confining a snippet to the applications the person chose")
struct ApplicationScopeTests {
    private static let mail = "com.example.Mail"
    private static let chat = "com.example.Chat"

    @Test("an empty list applies everywhere, an unknown front included")
    func emptyAppliesEverywhere() {
        #expect(ApplicationScope.admits([], in: Self.mail))
        #expect(ApplicationScope.admits([], in: nil))
    }

    @Test("a list applies only in its applications, whatever the identifier's case")
    func listAppliesOnlyThere() {
        #expect(ApplicationScope.admits([Self.mail], in: "COM.EXAMPLE.MAIL"))
        #expect(!ApplicationScope.admits([Self.mail], in: Self.chat))
        #expect(!ApplicationScope.admits([Self.mail], in: nil))
    }

    @Test("a kept list is trimmed, without blanks, one per application, in the order chosen")
    func normalisedList() {
        #expect(
            ApplicationScope.normalised([" \(Self.chat) ", "", Self.mail, "com.example.chat"])
                == [Self.chat, Self.mail])
    }

    @Test("a snippet file from before scopes opens as a snippet that fires everywhere")
    func oldSnippetDecodesUnscoped() throws {
        let old = Data(
            (#"[{"id":"7D4F5E2A-1C3B-4A5D-9E8F-0A1B2C3D4E5F","trigger":"sign off","#
                + #""expansion":"Thanks","created":0,"timesUsed":3}]"#).utf8)
        let snippet = try #require(try JSONDecoder().decode([Snippet].self, from: old).first)
        #expect(snippet.applications.isEmpty)
        #expect(snippet.applies(in: Self.chat))
    }

    @Test("a scoped snippet keeps its applications through a write, and an unscoped one writes no key")
    func snippetRoundTrip() throws {
        let scoped = Snippet(
            trigger: "sign off", expansion: "Thanks", created: .distantPast, applications: [Self.mail])
        let again = try JSONDecoder().decode(Snippet.self, from: JSONEncoder().encode(scoped))
        #expect(again == scoped)
        #expect(again.used(at: .distantFuture).applications == [Self.mail])
        let plain = Snippet(trigger: "sign off", expansion: "Thanks", created: .distantPast)
        #expect(!String(decoding: try JSONEncoder().encode(plain), as: UTF8.self).contains("applications"))
    }
}
