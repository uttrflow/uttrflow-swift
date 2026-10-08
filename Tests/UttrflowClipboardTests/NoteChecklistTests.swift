import Testing

@testable import UttrflowClipboard

@Suite("E5 · reading checklist progress")
struct NoteChecklistTests {
    static let github = """
        <ul><li class="task-list-item"><input type="checkbox"> milk</li>\
        <li class="task-list-item"><input type="checkbox" checked> bread</li></ul>
        """
    static let appleNotes = """
        <ul class="checklist"><li class="unchecked">milk</li>\
        <li class="checked">bread</li></ul>
        """
    static let tiptap = """
        <ul data-type="taskList"><li data-checked="false">milk</li>\
        <li data-checked="true">bread</li></ul>
        """

    @Test("every dialect real editors write is read", arguments: [github, appleNotes, tiptap])
    func readsEveryDialect(_ html: String) {
        #expect(NoteChecklist.items(in: html).map(\.isChecked) == [false, true])
        let progress = NoteChecklist.progress(in: html)
        #expect(progress?.done == 1)
        #expect(progress?.total == 2)
    }

    @Test("a note with no boxes has no progress to report")
    func noBoxes() {
        #expect(NoteChecklist.progress(in: "<ul><li>milk</li><li>bread</li></ul>") == nil)
        #expect(NoteChecklist.items(in: "plain words").isEmpty)
    }

    @Test("an item in a labelled checklist is a box even when it does not mark itself")
    func bareItemInLabelledChecklist() {
        let html = "<ul class=\"checklist\"><li class=\"checked\">Milk</li><li>Tea</li></ul>"
        #expect(NoteChecklist.items(in: html).map(\.isChecked) == [true, false])
        #expect(NoteChecklist.progress(in: html)?.total == 2)
    }

    @Test(
        "counts exactly the boxes the plain form writes",
        arguments: [
            github, appleNotes, tiptap,
            "<ul class=\"checklist\"><li>Pack</li><li class=\"checked\">Print</li></ul>",
            "<ul><li role=\"checkbox\" aria-checked=\"true\">Filed</li></ul>",
            "<ul><li class=\"checklist-item\">Pack</li></ul>",
            "<ul><li class=\"checked\"><input type=\"checkbox\"> Pack</li></ul>",
            "<p><input type=\"checkbox\" checked> Water</p><div hidden><input type=\"checkbox\"></div>",
            "<ul class=\"checklist\"><li class=\"checked\">Trip<ul class=\"checklist\"><li>Adapter</li></ul></li></ul>",
        ])
    func agreesWithPlainForm(_ html: String) {
        let written = RichTextPlainForm.plainText(fromHTML: html)
            .split(separator: "\n")
            .map { $0.drop(while: \.isWhitespace) }
            .compactMap { line in line.hasPrefix("[x] ") ? true : line.hasPrefix("[ ] ") ? false : nil }
        #expect(NoteChecklist.items(in: html).map(\.isChecked) == written)
    }

    @Test("unchecked is not mistaken for checked")
    func uncheckedIsNotChecked() {
        let html = "<ul class=\"checklist\"><li class=\"unchecked\">milk</li></ul>"
        #expect(NoteChecklist.items(in: html).map(\.isChecked) == [false])
        #expect(NoteChecklist.progress(in: html)?.done == 0)
    }

    @Test("both XHTML and HTML checked attributes are read")
    func bothSpellings() {
        let xhtml = "<input type=\"checkbox\" checked=\"checked\" />"
        let bare = "<input type=\"checkbox\" checked>"
        #expect(NoteChecklist.items(in: xhtml).map(\.isChecked) == [true])
        #expect(NoteChecklist.items(in: bare).map(\.isChecked) == [true])
    }

    @Test("single-quoted and unquoted checkbox types are recognized")
    func recognizesCheckboxTypeSpellings() {
        #expect(NoteChecklist.items(in: "<input type='checkbox'>").map(\.isChecked) == [false])
        #expect(NoteChecklist.items(in: "<input type=checkbox checked/>").map(\.isChecked) == [true])
        #expect(NoteChecklist.items(in: "<input type=\"text\" checked>").isEmpty)
    }

    @Test("an unclosed class quote does not create a checked item")
    func unclosedClassQuoteIsNotACheckbox() {
        #expect(NoteChecklist.items(in: "<li class=\"checked").isEmpty)
    }

    @Test("aria-checked is not the checked attribute")
    func ariaCheckedIsNotChecked() {
        let html = "<ul><li><input type=\"checkbox\" aria-checked=\"false\"> Buy milk</li></ul>"
        #expect(NoteChecklist.items(in: html).map(\.isChecked) == [false])
    }

    @Test("an unclosed tag does not crash or eat the rest")
    func malformed() {
        #expect(NoteChecklist.items(in: "<input type=\"checkbox\"").isEmpty)
        #expect(NoteChecklist.items(in: "<li class=\"checked\"").isEmpty)
        #expect(NoteChecklist.items(in: "").isEmpty)
    }
}
