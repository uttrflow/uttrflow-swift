// Tests for drawing the naming, move and delete sheets, and the hint that follows them.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

@Suite("Drawing the naming sheet")
struct PanelAliasSheetPresentationTests {
    /// A clip with no alias.
    static let plain = PanelFixture.clip("postgres://prod", minutesAgo: 1)
    /// A clip that holds "taken".
    static let named = PanelFixture.clip("the other one", minutesAgo: 2, alias: "taken")
    /// Both.
    static let clips = [plain, named]

    /// The naming sheet for a clip with this draft typed.
    static func sheet(_ draft: String, for clip: Clip = plain) -> PanelSheetPresentation? {
        let panel = PanelFixture.panel(clips).applying([.alias(clip.id), .draft(draft)]).state
        return PanelPresenter.present(panel).sheet
    }

    @Test("no sheet is drawn when none is open")
    func nothingByDefault() {
        #expect(PanelPresenter.present(PanelFixture.panel(Self.clips)).sheet == nil)
    }

    @Test("the title says whether this is naming or renaming")
    func titleFollowsTheClip() {
        #expect(Self.sheet("")?.title == "Name this clip")
        #expect(Self.sheet("taken", for: Self.named)?.title == "Rename this clip")
    }

    /// The correction is reported, never applied to the field, or nobody could type in it.
    @Test("the field shows exactly what was typed, uncorrected")
    func theFieldIsNotRewritten() {
        #expect(Self.sheet("PG Prod")?.draft == "PG Prod")
    }

    @Test("F4 · the note says what will actually be saved")
    func theNoteExplainsTheCorrection() {
        #expect(Self.sheet("PG Prod")?.note?.contains("pgprod") == true)
        #expect(Self.sheet("pgprod")?.note == nil, "nothing was corrected, so nothing is said")
        #expect(Self.sheet("/pgprod")?.note == nil, "the slash is the convention, not a mistake")
    }

    /// F3 — "taken" without "by what" leaves the user guessing at a clip they cannot see.
    @Test("F3 · the conflict names the clip that holds the alias")
    func theConflictNamesTheHolder() {
        let sheet = Self.sheet("taken")

        #expect(sheet?.conflict?.contains("the other one") == true)
        #expect(sheet?.isConfirmEnabled == false)
    }

    @Test("mixed writing systems explain why a name cannot be saved")
    func mixedScriptNameHasClearConflict() {
        let clip = PanelFixture.clip("first")
        let panel = PanelFixture.panel([clip]).applying([.alias(clip.id), .draft("pаypal")]).state
        let sheet = PanelPresenter.present(panel).sheet

        #expect(sheet?.conflict == "Use one writing system in a name")
        #expect(sheet?.isConfirmEnabled == false)
    }

    @Test("the conflict never names a masked secret by its text, and does once it is revealed")
    func theConflictHidesAMaskedHolder() {
        let secret = PanelFixture.clip("Zx9kLmQ2rT7p", kind: .secret, minutesAgo: 2, alias: "db")
        func conflict(revealed: Set<Clip.ID>) -> String? {
            let panel = PanelFixture.panel([Self.plain, secret], revealed: revealed)
                .applying([.alias(Self.plain.id), .draft("db")]).state
            return PanelPresenter.present(panel).sheet?.conflict
        }

        #expect(conflict(revealed: []) == "“db” already belongs to a hidden credential")
        #expect(conflict(revealed: [secret.id])?.contains("Zx9kLmQ2rT7p") == true)
    }

    /// F5 — the button must agree with what Return does, or it looks broken.
    @Test("the button is enabled exactly when Return would save something")
    func theButtonMatchesReturn() {
        #expect(Self.sheet("pgprod")?.isConfirmEnabled == true)
        #expect(Self.sheet("taken")?.isConfirmEnabled == false)
        #expect(Self.sheet("")?.isConfirmEnabled == false, "nothing typed, nothing to save")
    }

    /// "Save" over an action that takes the name away would be a lie about what happens.
    @Test("emptying an existing name reads as removing it")
    func removingReadsAsRemoving() {
        let sheet = Self.sheet("", for: Self.named)

        #expect(sheet?.confirmTitle == "Remove name")
        #expect(sheet?.isConfirmEnabled == true)
    }
}

@Suite("Drawing the move sheet")
struct PanelMoveSheetPresentationTests {
    /// Two collections and a loose clip.
    static let clips = [
        PanelFixture.clip("one", minutesAgo: 1, category: "Work"),
        PanelFixture.clip("two", minutesAgo: 2, category: "Work"),
        PanelFixture.clip("three", minutesAgo: 3, category: "Servers"),
        PanelFixture.clip("loose", minutesAgo: 4),
    ]

    /// The move sheet for the loose clip with this draft.
    static func sheet(_ draft: String = "") -> PanelSheetPresentation? {
        let panel = PanelFixture.panel(clips)
            .applying([.move(clips[3].id), .draft(draft)]).state
        return PanelPresenter.present(panel).sheet
    }

    /// G1 — two collections told apart by nothing is how a clip lands in the wrong one.
    @Test("every collection is offered, with how many clips it holds")
    func collectionsCarryTheirCounts() {
        let collections = Self.sheet()?.collections ?? []

        #expect(collections.map(\.name) == ["Servers", "Work"])
        #expect(collections.first { $0.name == "Work" }?.count == 2)
        #expect(collections.first { $0.name == "Servers" }?.count == 1)
    }

    @Test("the collection the clip is already in is marked as its own")
    func theCurrentOneIsMarked() {
        let panel = PanelFixture.panel(Self.clips).applying(.move(Self.clips[0].id)).state
        let collections = PanelPresenter.present(panel).sheet?.collections ?? []

        #expect(collections.first { $0.isCurrent }?.name == "Work")
    }

    /// G3 — warned before the second chip exists, not after, when two read the same word.
    @Test("a name that differs only in case says which collection it will join")
    func theDuplicateIsFlagged() {
        #expect(Self.sheet("work")?.note?.contains("Work") == true)
        #expect(Self.sheet("Work")?.note == nil, "an exact match is simply choosing it")
        #expect(Self.sheet("Snippets")?.note == nil, "a genuinely new name says nothing")
    }

    @Test("Move is disabled until something is named")
    func moveNeedsAName() {
        #expect(Self.sheet("")?.isConfirmEnabled == false)
        #expect(Self.sheet("   ")?.isConfirmEnabled == false)
        #expect(Self.sheet("Snippets")?.isConfirmEnabled == true)
    }
}

/// F8 — the note is the answer to "why is this one asking me when the others did not".
@Suite("Drawing the delete confirmation")
struct PanelDeleteSheetPresentationTests {
    /// The delete sheet for a clip.
    static func sheet(_ clip: Clip) -> PanelSheetPresentation? {
        let panel = PanelFixture.panel([clip]).applying(.delete(clip.id)).state
        return PanelPresenter.present(panel).sheet
    }

    @Test("it says what else is about to be lost")
    func itNamesWhatIsLost() {
        let aliased = PanelFixture.clip("x", minutesAgo: 1, alias: "pgprod")
        let filed = PanelFixture.clip("y", minutesAgo: 1, category: "Work")
        let pinned = PanelFixture.clip("z", minutesAgo: 1, isPinned: true)

        #expect(Self.sheet(aliased)?.note == "It answers to “pgprod”, which will be gone too.")
        #expect(Self.sheet(filed)?.note == "It is filed under “Work”.")
        #expect(Self.sheet(pinned)?.note == "It is pinned.")
    }

    /// Only a kept clip asks; an ordinary one goes at once, and the undo offer pays for that.
    @Test("an ordinary clip is deleted without a question")
    func ordinaryClipCopy() {
        let clip = PanelFixture.clip("x", minutesAgo: 1)
        let response = PanelFixture.panel([clip]).applying(.delete(clip.id))

        #expect(response.outcome == .change(.delete(clip.id)))
        #expect(PanelPresenter.present(response.state).sheet == nil)
    }

    @Test("a masked credential's contents never appear in the delete note")
    func maskedCredentialCopy() {
        let secret = PanelFixture.clip("Zx9kLmQ2rT7p", kind: .secret, minutesAgo: 1, isPinned: true)
        let note = Self.sheet(secret)?.note

        #expect(note == "It is pinned.")
        #expect(note?.contains("Zx9kLmQ2rT7p") == false)
    }

    @Test("the button says Delete, not OK")
    func theButtonNamesTheAction() {
        let sheet = Self.sheet(PanelFixture.clip("x", minutesAgo: 1, alias: "a"))

        #expect(sheet?.confirmTitle == "Delete")
        #expect(sheet?.kind == .confirmingDelete)
    }
}

@Suite("Drawing the Make Note confirmation")
struct PanelMakeNoteSheetPresentationTests {
    /// A plain clip that can become a note.
    static let clip = PanelFixture.clip("three things to do", minutesAgo: 1)

    @Test("it names the action and says the plain text stays unchanged")
    func itExplainsTheAction() {
        let panel = PanelFixture.panel([Self.clip]).applying(.makeNote(Self.clip.id)).state
        let sheet = PanelPresenter.present(panel).sheet

        #expect(sheet?.kind == .confirmingMakeNote)
        #expect(sheet?.title == "Make this clip a note?")
        #expect(
            sheet?.note
                == "The original text stays unchanged. This note formatting cannot be undone.")
        #expect(sheet?.confirmTitle == "Make note")
        #expect(sheet?.isConfirmEnabled == true)
        #expect(sheet?.isConfirmDestructive == false)
    }
}

/// The keys change meaning while a sheet is open, so the line that teaches them changes too.
@Suite("The hint follows what is open")
struct PanelSheetHintTests {
    @Test("the hint teaches the sheet's keys, not the list's")
    func theHintFollowsTheSheet() {
        let clip = PanelFixture.clip("x", minutesAgo: 1)
        let browsing = PanelPresenter.present(PanelFixture.panel([clip]))
        let naming = PanelPresenter.present(
            PanelFixture.panel([clip]).applying(.alias(clip.id)).state)

        #expect(browsing.hint == PanelPresenter.hint)
        #expect(naming.hint == PanelPresenter.sheetHint)
        #expect(naming.hint.contains("esc to go back"))
    }
}
