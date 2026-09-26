// Tests for notes from the panel: promoting a plain clip.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// E6 — a note is a second representation, and the panel can make one from a plain clip.
@Suite("E6 · notes from the panel")
struct PanelNoteTests {
    /// A plain clip.
    static let plain = PanelFixture.clip("three things to do", minutesAgo: 1)
    /// A two-item checklist, one item done.
    static let note = Clip(
        text: "milk\nbread", kind: .text, copiedAt: PanelFixture.now,
        richText: """
            <ul><li class="task-list-item"><input type="checkbox"> milk</li>\
            <li class="task-list-item"><input type="checkbox" checked> bread</li></ul>
            """)

    /// The row for one clip.
    static func row(_ clip: Clip) -> PanelRow {
        PanelPresenter.present(PanelFixture.panel([clip])).rows[0]
    }

    // MARK: E6

    @Test("a plain clip is offered promotion, and a note is not")
    func offeredOnce() {
        #expect(Self.row(Self.plain).actions.map(\.title).contains("Make a note"))
        #expect(!Self.row(Self.note).actions.map(\.title).contains("Make a note"))
    }

    /// Promoting twice would replace what the user wrote with a fresh copy of its own plain text.
    @Test("promoting a clip that is already a note does nothing")
    func neverPromotesTwice() {
        #expect(PanelFixture.panel([Self.note]).applying(.makeNote(Self.note.id)).outcome == .open)
    }

    /// The plain text stays recoverable because neither form is ever derived from the other.
    @Test("promoting leaves the plain text exactly as it was")
    func plainSurvives() {
        let response = PanelFixture.panel([Self.plain]).applying(.makeNote(Self.plain.id))

        guard case .change(.setRichText(let id, let note)) = response.outcome else {
            Issue.record("did not promote")
            return
        }
        #expect(id == Self.plain.id)
        #expect(note.contains("three things to do"))
        // Nothing in the change touches `text`; the store method it maps to cannot.
        #expect(Self.plain.text == "three things to do")
    }

    /// Not Markdown: "# 3 things" is a note about three things, and guessing a heading rewrites it.
    @Test("promotion interprets nothing, and escapes what would become markup")
    func promotionDoesNotGuess() {
        let hashed = PanelFixture.clip("# 3 things & <b>one</b>", minutesAgo: 1)
        let response = PanelFixture.panel([hashed]).applying(.makeNote(hashed.id))

        guard case .change(.setRichText(_, let note)) = response.outcome else {
            Issue.record("did not promote")
            return
        }
        #expect(!note.contains("<h1"), "a hash is not a heading")
        #expect(note.contains("&lt;b&gt;"), "and the user's angle brackets are their words")
        #expect(note.contains("&amp;"))
    }

    @Test("line breaks become paragraphs, so a promoted note reads as it was written")
    func linesBecomeParagraphs() {
        let lines = PanelFixture.clip("one\ntwo\nthree", minutesAgo: 1)
        let response = PanelFixture.panel([lines]).applying(.makeNote(lines.id))

        guard case .change(.setRichText(_, let note)) = response.outcome else {
            Issue.record("did not promote")
            return
        }
        #expect(note == "<p>one</p><p>two</p><p>three</p>")
    }
}
