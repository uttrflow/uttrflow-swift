// Tests for deleting, naming and filing from the panel, what esc means, and what a change tells the app.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// An ordinary clip goes at once because undo makes asking pointless; a kept one asks first.
@Suite("Deleting a clip")
struct PanelDeleteTests {
    /// Nothing kept about it.
    static let ordinary = PanelFixture.clip("just some text", minutesAgo: 1)
    /// Pinned.
    static let pinned = PanelFixture.clip("kept", minutesAgo: 2, isPinned: true)
    /// Named.
    static let aliased = PanelFixture.clip("named", minutesAgo: 3, alias: "thing")
    /// Filed.
    static let filed = PanelFixture.clip("filed", minutesAgo: 4, category: "Work")

    /// All four.
    static let every = [ordinary, pinned, aliased, filed]

    @Test("an ordinary clip goes immediately, with no dialog")
    func ordinaryGoesAtOnce() {
        let response = PanelFixture.panel(Self.every).applying(.delete(Self.ordinary.id))

        #expect(response.outcome == .change(.delete(Self.ordinary.id)))
        #expect(response.state.sheet == nil)
    }

    /// Pinned, aliased or filed — all three are the user having said this one matters.
    @Test(
        "a clip the user kept is confirmed first",
        arguments: [pinned, aliased, filed]
    )
    func keptClipsAsk(clip: Clip) {
        let response = PanelFixture.panel(Self.every).applying(.delete(clip.id))

        #expect(response.state.sheet == .confirmingDelete(clip.id))
        #expect(response.outcome == .open, "nothing is deleted until the question is answered")
    }

    @Test("confirming carries out the delete")
    func confirmingDeletes() {
        let panel = PanelFixture.panel(Self.every).applying(.delete(Self.pinned.id)).state

        let response = panel.applying(.return)

        #expect(response.outcome == .change(.delete(Self.pinned.id)))
        #expect(response.state.sheet == nil)
    }

    /// Backing out of a confirmation must leave the clip alone and leave the panel up.
    @Test("escaping the confirmation deletes nothing and keeps the panel open")
    func escapingConfirmsNothing() {
        let panel = PanelFixture.panel(Self.every).applying(.delete(Self.pinned.id)).state

        let response = panel.applying(.escape)

        #expect(response.outcome == .open, "not dismissed — the list is still wanted")
        #expect(response.state.sheet == nil)
    }

    @Test("deleting a clip that is no longer listed does nothing at all")
    func deletingSomethingGone() {
        let response = PanelFixture.panel(Self.every).applying(.delete(UUID()))

        #expect(response.outcome == .open)
        #expect(response.state.sheet == nil)
    }
}

/// F1, F2, F3 — naming a clip, and the two ways it can fail to be worth saving.
@Suite("Naming a clip from the panel")
struct PanelAliasSheetTests {
    /// Unnamed.
    static let plain = PanelFixture.clip("postgres://prod", minutesAgo: 1)
    /// Holds the alias "taken".
    static let named = PanelFixture.clip("something else", minutesAgo: 2, alias: "taken")

    @Test("the field opens showing the alias the clip already has")
    func opensWithTheCurrentAlias() {
        let panel = PanelFixture.panel([Self.plain, Self.named])

        #expect(
            panel.applying(.alias(Self.named.id)).state.sheet
                == .aliasing(Self.named.id, draft: "taken"))
        #expect(
            panel.applying(.alias(Self.plain.id)).state.sheet
                == .aliasing(Self.plain.id, draft: ""))
    }

    @Test("typing a name and pressing Return saves the corrected form")
    func savesTheCorrectedForm() {
        let response = PanelFixture.panel([Self.plain, Self.named])
            .applying([.alias(Self.plain.id), .draft("/PG Prod"), .return])

        #expect(response.outcome == .change(.setAlias(Self.plain.id, "pgprod")))
    }

    /// Return on a taken alias leaves the sheet up with the conflict on screen, rather than looking broken.
    @Test("Return on an alias somebody else holds keeps the sheet open")
    func aTakenAliasDoesNotSave() {
        let response = PanelFixture.panel([Self.plain, Self.named])
            .applying([.alias(Self.plain.id), .draft("taken"), .return])

        #expect(response.outcome == .open)
        #expect(response.state.sheet == .aliasing(Self.plain.id, draft: "taken"))
    }

    @Test("emptying the field is how an alias is removed")
    func emptyingRemovesIt() {
        let response = PanelFixture.panel([Self.plain, Self.named])
            .applying([.alias(Self.named.id), .draft(""), .return])

        #expect(response.outcome == .change(.setAlias(Self.named.id, nil)))
    }

    /// Return behind a half-typed alias must not paste the clip being named.
    @Test("Return belongs to the sheet, not the list, while the sheet is open")
    func returnDoesNotPasteBehindASheet() {
        let response = PanelFixture.panel([Self.plain, Self.named])
            .applying([.alias(Self.plain.id), .return])

        if case .insert = response.outcome {
            Issue.record("Return inserted a clip from behind an open sheet")
        }
    }
}

/// G1, G2, G3 — filing a clip, and the duplicate-name trap.
@Suite("Filing a clip into a collection")
struct PanelMoveSheetTests {
    /// One filed clip and one loose one.
    static let clips = [
        PanelFixture.clip("one", minutesAgo: 1, category: "Work"),
        PanelFixture.clip("two", minutesAgo: 2),
    ]

    @Test("the move sheet opens empty, because nothing has been chosen yet")
    func opensEmpty() {
        let response = PanelFixture.panel(Self.clips).applying(.move(Self.clips[1].id))

        #expect(response.state.sheet == .moving(Self.clips[1].id, draft: ""))
    }

    @Test("naming a new collection files the clip into it")
    func filesIntoANewOne() {
        let response = PanelFixture.panel(Self.clips)
            .applying([.move(Self.clips[1].id), .draft("Servers"), .return])

        #expect(response.outcome == .change(.setCategory(Self.clips[1].id, "Servers")))
    }

    /// Two collections with the same name are two things nobody could tell apart in a row of chips.
    @Test("a name that already exists files it there rather than making a second one")
    func reusesAnExistingName() {
        let response = PanelFixture.panel(Self.clips)
            .applying([.move(Self.clips[1].id), .draft("work"), .return])

        #expect(
            response.outcome == .change(.setCategory(Self.clips[1].id, "Work")),
            "filed under the collection that exists, spelt as it already is")
    }

    @Test("Return on an empty name keeps the sheet open")
    func emptyNameDoesNothing() {
        let response = PanelFixture.panel(Self.clips)
            .applying([.move(Self.clips[1].id), .draft("   "), .return])

        #expect(response.outcome == .open)
        #expect(response.state.sheet != nil)
    }
}

/// A sheet changes what two keys mean, and getting it wrong throws away the list or the clip.
@Suite("What esc means depends on what is open")
struct PanelSheetEscapeTests {
    /// A plain clip.
    static let clip = PanelFixture.clip("a clip", minutesAgo: 1)

    @Test("with no sheet, esc closes the panel")
    func escapeClosesThePanel() {
        #expect(PanelFixture.panel([Self.clip]).applying(.escape).outcome == .dismissed)
    }

    /// Closing the whole panel on backing out of naming would throw away the list with no way back.
    @Test("with a sheet open, esc closes only the sheet")
    func escapeClosesOnlyTheSheet() {
        let panel = PanelFixture.panel([Self.clip]).applying(.alias(Self.clip.id)).state

        let response = panel.applying(.escape)

        #expect(response.outcome == .open)
        #expect(response.state.sheet == nil)
    }

    @Test("a second esc then closes the panel")
    func theSecondEscapeCloses() {
        let response = PanelFixture.panel([Self.clip])
            .applying([.alias(Self.clip.id), .escape, .escape])

        #expect(response.outcome == .dismissed)
    }

    @Test("typing with no sheet open changes nothing")
    func draftingWithoutASheet() {
        let panel = PanelFixture.panel([Self.clip])

        #expect(panel.applying(.draft("stray")).state == panel)
    }
}

/// A change must never be mistaken for a dismissal, or filing one clip would shut the panel.
@Suite("What a change tells the app to do")
struct PanelChangeEffectTests {
    @Test("a change is applied and redrawn, never closed")
    func changesKeepThePanelUp() {
        let id = UUID()

        #expect(PanelOutcome.change(.delete(id)).effect == .applyAndRedraw(.delete(id)))
        #expect(PanelOutcome.change(.setAlias(id, "x")).effect == .applyAndRedraw(.setAlias(id, "x")))
        #expect(PanelOutcome.change(.delete(id)).effect != .close)
    }
}
