// Tests for editing, searching and noting every pronunciation of a dictionary entry.

import Foundation
import Testing
import UttrflowDictionary

@testable import UttrflowUX

@Suite("Every pronunciation in the editor, search and notes")
struct SeveralPronunciationsEditorTests {
    private func zentrova(_ sounds: [String]) -> DictionaryEntry {
        DictionaryEntry(
            word: "Zentrova", pronunciations: sounds, origin: .added, firstSeen: HistoryFixture.now)
    }

    @Test("the field splits at commas, trimmed and bounded, and shows a list joined the same way")
    func fieldRoundTrips() {
        #expect(
            DictionaryEntry.pronunciations(inField: " zen trova , jen trova,,zen trova ") == [
                "zen trova", "jen trova",
            ])
        #expect(zentrova(["zen trova", "jen trova"]).pronunciationField == "zen trova, jen trova")
        #expect(
            DictionaryEntry.pronunciations(inField: zentrova(["a", "b"]).pronunciationField) == ["a", "b"])
    }

    @Test("a refusal of any one pronunciation is the editor's problem")
    func refusesEachInEditor() throws {
        let fine = try #require(
            HistoryFixture.dictionary(
                draft: DictionaryDraft(word: "Zentrova", pronunciation: "zen trova, jen trova")
            ).editor)
        #expect(fine.problem == nil)
        let refused = try #require(
            HistoryFixture.dictionary(
                draft: DictionaryDraft(word: "Zentrova", pronunciation: "zen trova, one two three four")
            ).editor)
        #expect(refused.problem != nil)
        #expect(!refused.canSave)
    }

    @Test("Replace on a duplicate keeps its pronunciations and adds the one typed")
    func replaceAddsPronunciation() throws {
        let existing = zentrova(["zen trova"])
        let editor = try #require(
            HistoryFixture.dictionary(
                entries: [existing], draft: DictionaryDraft(word: "Zentrova", pronunciation: "sent rover")
            ).editor)
        #expect(editor.kept == ["zen trova"])
        #expect(
            editor.replace?.intent
                == .replaceWord(
                    existing.id, word: "Zentrova", pronunciation: "zen trova, sent rover", applications: []))
    }

    @Test("search finds an entry by its second pronunciation")
    func searchMatchesAny() {
        let page = HistoryFixture.dictionary(
            entries: [zentrova(["zen trova", "jen trova"])], query: "jen trova")
        #expect(page.rows.map(\.word) == ["Zentrova"])
    }

    @Test("a snippet trigger holding a second pronunciation is noted")
    func snippetNoteMatchesAny() {
        let note = SnippetsPresenter.dictionaryNote(
            for: "send jen trova invoice", in: [zentrova(["zen trova", "jen trova"])])
        #expect(note == "Dictation may write “jen trova” as “Zentrova”, from your Dictionary.")
    }
}
