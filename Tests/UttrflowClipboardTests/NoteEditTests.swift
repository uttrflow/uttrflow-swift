// Tests for editing a note made with "Make a note": the plain form in, a rebuilt note out.
import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("Editing a note")
struct NoteEditTests {
    @Test("box lines become checklist items and every other line a paragraph")
    func boxLinesBecomeItems() {
        let html = NotePromotion.editedNote(from: "Shop\n[x] Milk\n[ ] <Eggs>\nThen home")

        #expect(
            html == "<p>Shop</p><ul class=\"checklist\"><li class=\"checked\">Milk</li>"
                + "<li class=\"unchecked\">&lt;Eggs&gt;</li></ul><p>Then home</p>")
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "Shop\n[x] Milk\n[ ] <Eggs>\nThen home")
        #expect(NoteChecklist.progress(in: html)! == (1, 2))
    }

    @Test("a note made with Make a note, and one Edit wrote, can be edited without loss")
    func writtenNotesAreEditable() {
        #expect(NotePromotion.isEditableNote(NotePromotion.note(from: "one\ntwo")))
        #expect(NotePromotion.isEditableNote(NotePromotion.editedNote(from: "a\n[ ] b")))
    }

    @Test(
        "a formatted copy plain editing would lose stays uneditable",
        arguments: [
            "<p><b>bold</b></p>", "<ul><li>[ ] Milk</li></ul>", "<h1>Title</p>",
            "<p><a href=\"https://example.com\">x</a></p>",
        ])
    func formattedCopiesAreNot(html: String) {
        #expect(!NotePromotion.isEditableNote(html))
    }

    @Test("an edited note keeps its checklist and plain form together across a relaunch")
    func editedNoteRoundTrips() async throws {
        let folder = try TemporaryFolder()
        let clip = Clip(text: "Shop\nMilk", kind: .text, copiedAt: Date())
        _ = try await folder.store.record(clip, keeping: folder.retention)
        _ = try await folder.store.setRichText(
            NotePromotion.note(from: clip.text), of: clip.id, keeping: folder.retention)

        _ = try await folder.store.setText(
            "Shop\n[x] Milk\n[ ] Eggs", of: clip.id, keeping: folder.retention)

        let reopened = ClipboardStore(file: folder.url.appending(path: "clipboard.json"))
        let clips = await reopened.clips(keeping: folder.retention)
        let after = try #require(clips.first { $0.id == clip.id })
        #expect(after.text == "Shop\n[x] Milk\n[ ] Eggs")
        let boxes = after.richText.map(NoteChecklist.items(in:))
        #expect(boxes == [.init(isChecked: true), .init(isChecked: false)])
    }

    @Test("editing a formatted copy still clears its formatted form")
    func formattedCopyIsCleared() async throws {
        let folder = try TemporaryFolder()
        let clip = Clip(text: "bold", kind: .text, copiedAt: Date(), richText: "<p><b>bold</b></p>")
        _ = try await folder.store.record(clip, keeping: folder.retention)

        let after = try await folder.store.setText("plain", of: clip.id, keeping: folder.retention)

        #expect(after.first { $0.id == clip.id }?.richText == nil)
    }
}
