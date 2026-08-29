import Testing

@testable import UttrflowClipboard

/// E5 — a ticked box is content, not decoration. These are mostly about the note *around*
/// the box surviving untouched, because this is the only thing in the app that edits a
/// user's own writing in place.
@Suite("E5 · ticking a box in a note")
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

    @Test(
        "every dialect real editors write is read",
        arguments: [github, appleNotes, tiptap]
    )
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

    @Test(
        "ticking the first box ticks exactly that one",
        arguments: [github, appleNotes, tiptap]
    )
    func ticksOne(_ html: String) throws {
        let after = try #require(NoteChecklist.toggling(0, in: html))

        #expect(NoteChecklist.items(in: after).map(\.isChecked) == [true, true])
    }

    @Test(
        "and unticking works the same way round",
        arguments: [github, appleNotes, tiptap]
    )
    func unticksOne(_ html: String) throws {
        let after = try #require(NoteChecklist.toggling(1, in: html))

        #expect(NoteChecklist.items(in: after).map(\.isChecked) == [false, false])
    }

    /// The one that a substring test gets wrong every time: `unchecked` contains
    /// `checked`, so a careless match ticks every empty box in the note.
    @Test("an unchecked item is not mistaken for a checked one")
    func uncheckedIsNotChecked() {
        let html = "<ul class=\"checklist\"><li class=\"unchecked\">milk</li></ul>"

        #expect(NoteChecklist.items(in: html).map(\.isChecked) == [false])
        #expect(NoteChecklist.progress(in: html)?.done == 0)
    }

    /// A note is the user's writing. Ticking a box must change the box and not one other
    /// character of it.
    @Test("the words around the box come back untouched")
    func theNoteSurvives() throws {
        let html = """
            <h1>Release</h1><p>Before the cut:</p>\
            <ul><li class="task-list-item"><input type="checkbox"> run the tests</li></ul>\
            <p>Then post in #releases.</p>
            """

        let after = try #require(NoteChecklist.toggling(0, in: html))

        #expect(after.contains("<h1>Release</h1>"))
        #expect(after.contains("Before the cut:"))
        #expect(after.contains("run the tests"))
        #expect(after.contains("Then post in #releases."))
        #expect(NoteChecklist.items(in: after) == [NoteChecklist.Item(isChecked: true)])
    }

    /// `nil` rather than the unchanged note, so a caller can tell "nothing to tick" from
    /// "ticking it changed nothing" and never writes a no-op to disk.
    @Test("a box that is not there answers with nothing")
    func outOfRange() {
        #expect(NoteChecklist.toggling(0, in: "<p>no boxes</p>") == nil)
        #expect(NoteChecklist.toggling(5, in: Self.github) == nil)
        #expect(NoteChecklist.toggling(-1, in: Self.github) == nil)
    }

    /// Ticking and unticking has to be a round trip, or a note drifts every time it is
    /// touched — attributes accumulating, quotes changing style.
    @Test("ticking a box and unticking it returns the note it started as")
    func roundTrips() throws {
        for html in [Self.github, Self.appleNotes, Self.tiptap] {
            let ticked = try #require(NoteChecklist.toggling(0, in: html))
            let back = try #require(NoteChecklist.toggling(0, in: ticked))

            #expect(
                NoteChecklist.items(in: back).map(\.isChecked)
                    == NoteChecklist.items(in: html).map(\.isChecked))
        }
    }

    /// XHTML writes `checked="checked"`; HTML writes it bare. Both are ticked.
    @Test("both spellings of the checked attribute are read")
    func bothSpellings() {
        let xhtml = "<input type=\"checkbox\" checked=\"checked\" />"
        let bare = "<input type=\"checkbox\" checked>"

        #expect(NoteChecklist.items(in: xhtml).map(\.isChecked) == [true])
        #expect(NoteChecklist.items(in: bare).map(\.isChecked) == [true])
    }

    /// Malformed input is the user's clipboard, not a test fixture.
    @Test("an unclosed tag does not crash or eat the rest")
    func malformed() {
        #expect(NoteChecklist.items(in: "<input type=\"checkbox\"").isEmpty)
        #expect(NoteChecklist.toggling(0, in: "<li class=\"checked\"") == nil)
        #expect(NoteChecklist.items(in: "").isEmpty)
    }
}
