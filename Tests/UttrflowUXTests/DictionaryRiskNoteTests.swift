// Tests for the warning the dictionary editor shows for a word that sounds like ordinary words.
import Foundation
import UttrflowDictionary
import Testing

@testable import UttrflowUX

@Suite("The dictionary editor's risk note")
struct DictionaryRiskNoteTests {
    @Test("a word that sounds like ordinary words is noted, and an unusual one is not")
    func riskNote() {
        let risky = DictionaryPresenter.riskNote(for: DictionaryDraft(word: "Cee", pronunciation: "see"))
        #expect(risky?.hasPrefix("This may replace ordinary words") == true)
        #expect(DictionaryPresenter.riskNote(for: DictionaryDraft(word: "Zyxel")) == nil)
        #expect(DictionaryPresenter.riskNote(for: DictionaryDraft()) == nil)
    }

    @Test("the editor on the page carries the note and the risky word can still be saved")
    func editorCarriesNote() throws {
        let editor = try #require(
            HistoryFixture.dictionary(draft: DictionaryDraft(word: "Cee", pronunciation: "see")).editor)
        #expect(editor.riskNote?.hasPrefix("This may replace ordinary words") == true)
        #expect(editor.canSave)
        let plain = try #require(HistoryFixture.dictionary(draft: DictionaryDraft(word: "Zyxel")).editor)
        #expect(plain.riskNote == nil)
    }
}
