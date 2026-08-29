import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// G5 — a collection is a shelf, not part of a clip's identity, and renaming the shelf
/// must not touch what is on it.
@Suite("G5 · renaming a collection")
struct PanelRenameCategoryTests {
    static let clips = [
        PanelFixture.clip("one", minutesAgo: 1, alias: "first", category: "Work"),
        PanelFixture.clip("two", minutesAgo: 2, category: "Work"),
        PanelFixture.clip("three", minutesAgo: 3, category: "Servers"),
    ]

    static func panel(_ draft: String) -> PanelResponse {
        PanelFixture.panel(clips).applying([.renameCategory("Work"), .draft(draft)])
    }

    @Test("it opens with the current name, so it can be adjusted rather than retyped")
    func opensWithTheName() {
        let response = PanelFixture.panel(Self.clips).applying(.renameCategory("Work"))

        #expect(response.state.sheet == .renamingCategory("Work", draft: "Work"))
    }

    @Test("a new name renames the collection")
    func renames() {
        let response = Self.panel("Projects").state.applying(.return)

        #expect(response.outcome == .change(.renameCategory(from: "Work", to: "Projects")))
    }

    /// Renaming a collection looks like the kind of thing that might take the names inside
    /// it too, so the sheet says out loud that it does not.
    @Test("the sheet promises the clips keep their own names")
    func aliasesAreSafe() {
        let sheet = PanelPresenter.present(Self.panel("Projects").state).sheet

        #expect(sheet?.note?.contains("keep their own names") == true)
    }

    /// Renaming onto an existing name is a merge, and merging is not what was asked for.
    @Test("a name another collection already has is refused, and says so")
    func nameTaken() {
        let typed = Self.panel("servers")
        let sheet = PanelPresenter.present(typed.state).sheet

        #expect(sheet?.conflict?.contains("already a collection") == true)
        #expect(sheet?.isConfirmEnabled == false)
        #expect(typed.state.applying(.return).outcome == .open, "and Return does nothing")
    }

    @Test("renaming to the same name, or to nothing, does nothing")
    func noOpRenames() {
        #expect(Self.panel("Work").state.applying(.return).outcome == .open)
        #expect(Self.panel("   ").state.applying(.return).outcome == .open)
    }

    /// Otherwise the open tab would sit over a collection that no longer answers to that
    /// name until the next redraw.
    @Test("the open tab follows the rename")
    func theOpenTabFollows() {
        var panel = PanelFixture.panel(Self.clips)
        panel.category = "Work"

        let renamed = panel.applying([.renameCategory("Work"), .draft("Projects"), .return])

        #expect(renamed.state.category == "Projects")
    }
}

/// G6 — never silently orphaned. Deleting an empty collection and deleting one holding
/// forty clips are different acts, and only one of them needs thinking about.
@Suite("G6 · deleting a collection that holds clips")
struct PanelDeleteCategoryTests {
    static let clips = [
        PanelFixture.clip("one", minutesAgo: 1, category: "Work"),
        PanelFixture.clip("two", minutesAgo: 2, category: "Work"),
        PanelFixture.clip("three", minutesAgo: 3),
    ]

    @Test("it asks first, and the answer that loses nothing is the one preselected")
    func asksFirstAndSafely() {
        let response = PanelFixture.panel(Self.clips).applying(.deleteCategory("Work"))

        #expect(response.state.sheet == .deletingCategory("Work", keepingClips: true))
        #expect(response.outcome == .open, "nothing happens until it is answered")
    }

    @Test("the count is the question, and it is on screen")
    func theCountIsShown() {
        let panel = PanelFixture.panel(Self.clips).applying(.deleteCategory("Work")).state

        #expect(PanelPresenter.present(panel).sheet?.note?.contains("2 clip") == true)
    }

    @Test("keeping the clips moves them out rather than deleting them")
    func keepingTheClips() {
        let response = PanelFixture.panel(Self.clips)
            .applying([.deleteCategory("Work"), .return])

        #expect(response.outcome == .change(.deleteCategory("Work", movingClipsTo: nil)))
    }

    @Test("choosing to delete them says so, and warns that it cannot be undone")
    func deletingTheClips() {
        var panel = PanelFixture.panel(Self.clips)
        panel.sheet = .deletingCategory("Work", keepingClips: false)

        let sheet = PanelPresenter.present(panel).sheet
        #expect(sheet?.conflict?.contains("cannot be undone") == true)
        #expect(sheet?.confirmTitle == "Delete both")
        #expect(panel.applying(.return).outcome == .change(.deleteCategoryAndClips("Work")))
    }

    /// An empty collection is not a decision, and should not be dressed as one.
    @Test("an empty collection says it holds nothing")
    func emptyCollection() {
        var panel = PanelFixture.panel(Self.clips)
        panel.sheet = .deletingCategory("Nothing", keepingClips: true)

        #expect(PanelPresenter.present(panel).sheet?.note == "It holds nothing.")
    }

    /// The tab cannot stay open over a collection that has gone.
    @Test("the open tab closes with the collection")
    func theTabCloses() {
        var panel = PanelFixture.panel(Self.clips)
        panel.category = "Work"

        let deleted = panel.applying([.deleteCategory("Work"), .return])

        #expect(deleted.state.category == nil)
    }

    /// These two sheets are about a collection rather than a clip, and saying so with an
    /// invented identity would make every caller's "does the subject still exist" false.
    @Test("a sheet about a collection names no clip")
    func subjectIsTheCollection() {
        let sheet = PanelSheet.deletingCategory("Work", keepingClips: true)

        #expect(sheet.clip == nil)
        #expect(sheet.category == "Work")
    }
}
