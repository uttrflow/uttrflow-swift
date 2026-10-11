import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowUX

@Suite("The editors' one line for where a snippet fires or a word is offered")
struct ApplicationScopeLineTests {
    private static let mail = "com.example.Mail"

    @Test("an unconfined draft says every app and offers no way back, since it is already there")
    func everywhere() {
        let line = ApplicationScopeLine(applications: [])
        #expect(line.label == "Only in")
        #expect(line.summary == "Every app")
        #expect(line.clear == nil)
    }

    @Test("a confined draft names its applications and offers every app again")
    func confined() {
        let line = ApplicationScopeLine(applications: [Self.mail])
        #expect(line.summary != "Every app")
        #expect(!line.summary.isEmpty)
        #expect(line.clear == "Every App")
    }

    @Test("the snippet editor shows the draft's scope and saves it")
    func snippetEditorCarriesScope() throws {
        let editor = try #require(
            HistoryFixture.snippets(
                [], draft: SnippetDraft(trigger: "sign off", text: "Kind regards", applications: [Self.mail])
            ).editor)
        #expect(editor.scope == ApplicationScopeLine(applications: [Self.mail]))
        #expect(
            editor.save.intent
                == .saveSnippet(
                    trigger: "sign off", text: "Kind regards", applications: [Self.mail], replacing: nil))
    }

    @Test("the word editor shows the draft's scope, saves it, and keeps it when a try is offered")
    func wordEditorCarriesScope() throws {
        let draft = DictionaryDraft(word: "Zentrova", applications: [Self.mail])
        let editor = try #require(HistoryFixture.dictionary(draft: draft).editor)
        #expect(editor.scope == ApplicationScopeLine(applications: [Self.mail]))
        #expect(
            editor.save.intent == .saveWord(word: "Zentrova", pronunciation: "", applications: [Self.mail]))
        #expect(DictionaryPresenter.offering("zen trova", to: draft).applications == [Self.mail])
    }
}
