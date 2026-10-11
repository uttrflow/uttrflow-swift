import Testing
import UttrflowUX

@testable import Uttrflow

@Suite("Snippet editor keyboard actions")
struct SnippetEditorKeyboardTests {
    @Test("Return saves only a valid draft")
    func returnHonorsValidation() {
        let save = MainIntent.saveSnippet(trigger: "hello", text: "world", applications: [], replacing: nil)

        #expect(SnippetEditorKeyboard.saveIntent(canSave: true, save: save) == save)
        #expect(SnippetEditorKeyboard.saveIntent(canSave: false, save: save) == nil)
    }

    @Test("plain Return stays in the multiline text while Command-Return saves")
    func multilineReturn() {
        #expect(!SnippetEditorKeyboard.savesTextEditorReturn(command: false))
        #expect(SnippetEditorKeyboard.savesTextEditorReturn(command: true))
    }
}
