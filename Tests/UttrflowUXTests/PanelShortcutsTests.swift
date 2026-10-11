// Tests the chords a row's actions answer to, and the long moves through the list.
import Testing

@testable import UttrflowClipboard
@testable import UttrflowUX

@Suite("The panel's keyboard reaches every row action")
struct PanelShortcutsTests {
    /// The panel over one clip with that clip highlighted, in the slice that lists it.
    private func highlighting(_ clip: Clip) -> PanelPresentation {
        var snapshot = PanelFixture.panel([clip])
        snapshot.scope = clip.isPinned ? .pinned : .history
        snapshot.selection = clip.id
        return PanelPresenter.present(snapshot)
    }

    /// Everything the ⋯ menu offers has to be reachable without a pointer, which is the whole issue.
    @Test("every action a row offers carries the chord that performs it")
    func everyActionHasAChord() {
        let clip = PanelFixture.clip("let a = 1", kind: .code)
        var snapshot = PanelFixture.panel([clip])
        snapshot.selection = clip.id
        let row = PanelPresenter.present(snapshot).selectedRow

        let named = row?.actions.filter { $0.title != "Insert" } ?? []
        #expect(!named.isEmpty)
        #expect(named.allSatisfy { $0.shortcut != nil }, "only Insert is reached by ⏎ rather than a chord")
    }

    /// One chord per action, or two actions would answer the same keystroke and one would never fire.
    @Test("no two actions claim the same chord")
    func chordsAreDistinct() {
        let chords = PanelRowAction.allCases.map(\.chord)
        #expect(Set(chords).count == chords.count)
    }

    @Test("each row action keeps its documented shortcut")
    func actionShortcutMapping() {
        let expected: [(PanelRowAction, PanelChord)] = [
            (.reveal, PanelChord("r")),
            (.copy, PanelChord("c", shifted: true)),
            (.pin, PanelChord("p")),
            (.alias, PanelChord("n")),
            (.move, PanelChord("m")),
            (.edit, PanelChord("e")),
            (.format, PanelChord("f", shifted: true)),
            (.reindent, PanelChord("i", shifted: true)),
            (.makeNote, PanelChord("t", shifted: true)),
            (.secrecy, PanelChord("s", shifted: true)),
            (.delete, PanelChord("\u{7F}", shifted: true)),
        ]

        #expect(PanelRowAction.allCases.count == expected.count)
        for (action, chord) in expected {
            #expect(action.chord == chord, "\(action)")
        }
    }

    @Test("every offered row action resolves from its own shortcut")
    func everyOfferedActionResolvesFromItsShortcut() {
        let plain = PanelFixture.clip("Hello there")
        var plainSnapshot = PanelFixture.panel([plain])
        plainSnapshot.selection = plain.id

        let secret = PanelFixture.clip("sk-012345678901234567890123", kind: .secret)
        var secretSnapshot = PanelFixture.panel([secret])
        secretSnapshot.selection = secret.id

        let code = Clip(
            text: "func f() {\n\tlet x = 1\n        let y = 2\n}", kind: .code,
            copiedAt: PanelFixture.now, language: .swift)
        var codeSnapshot = PanelFixture.panel([code])
        codeSnapshot.selection = code.id
        codeSnapshot.formattableLanguages = [.swift]

        var resolvedChords: Set<PanelChord> = []
        for snapshot in [plainSnapshot, secretSnapshot, codeSnapshot] {
            let page = PanelPresenter.present(snapshot)
            for action in page.selectedRow?.actions ?? [] {
                guard let chord = action.shortcut else {
                    #expect(action.title == "Insert")
                    continue
                }
                resolvedChords.insert(chord)
                #expect(page.intent(for: chord) == action.intent, Comment(rawValue: action.title))
            }
        }
        #expect(resolvedChords == Set(PanelRowAction.allCases.map(\.chord)))
    }

    /// The search field owns these, and taking one would stop the user editing their own query.
    @Test("no chord is one the search field needs")
    func chordsLeaveTheFieldAlone() {
        let claimed = PanelRowAction.allCases.map(\.chord)
        for character in "acvxz" {
            #expect(!claimed.contains(PanelChord(character)), "⌘\(character.uppercased()) is the field's")
        }
        #expect(!claimed.contains(PanelChord("\u{7F}")), "⌘⌫ deletes to the start of the query")
    }

    @Test("a chord performs its action on the highlighted row")
    func chordActsOnTheHighlightedRow() {
        let clip = PanelFixture.clip("Hello there")
        var snapshot = PanelFixture.panel([clip])
        snapshot.selection = clip.id
        let page = PanelPresenter.present(snapshot)

        #expect(page.intent(for: PanelRowAction.alias.chord) == .alias(clip.id))
        #expect(page.intent(for: PanelRowAction.move.chord) == .move(clip.id))
        #expect(page.intent(for: PanelRowAction.delete.chord) == .delete(clip.id))
        #expect(page.intent(for: PanelRowAction.copy.chord) == .copy(clip.id))
    }

    /// The row offers whichever of the two applies, so one chord is both and neither can be wrong.
    @Test("the pin chord unpins a clip that is already pinned")
    func pinChordToggles() {
        let loose = PanelFixture.clip("Hello there")
        let kept = PanelFixture.clip("Kept", isPinned: true)

        #expect(highlighting(loose).intent(for: PanelRowAction.pin.chord) == .pin(loose.id))
        #expect(highlighting(kept).intent(for: PanelRowAction.pin.chord) == .unpin(kept.id))
    }

    /// The handler reads the row's own actions, so a chord cannot do what the ⋯ menu does not offer.
    @Test("a chord does nothing where the row does not offer that action")
    func chordDoesNothingWhereTheActionIsNotOffered() {
        let clip = PanelFixture.clip("Hello there")
        var snapshot = PanelFixture.panel([clip])
        snapshot.selection = clip.id
        let page = PanelPresenter.present(snapshot)

        #expect(page.intent(for: PanelRowAction.reveal.chord) == nil, "nothing is masked")
        #expect(page.intent(for: PanelRowAction.format.chord) == nil, "no formatter for plain text")
    }

    @Test("a chord does nothing when no row is highlighted")
    func chordDoesNothingWithNoSelection() {
        let page = PanelFixture.page([])

        #expect(page.intent(for: PanelRowAction.delete.chord) == nil)
    }

    /// A masked row is the one place Reveal is offered, and the one place its chord acts.
    @Test("the reveal chord acts only on a masked row")
    func revealChordOnAMaskedRow() {
        let secret = PanelFixture.clip("sk-012345678901234567890123", kind: .secret)
        var snapshot = PanelFixture.panel([secret])
        snapshot.selection = secret.id

        #expect(
            PanelPresenter.present(snapshot).intent(for: PanelRowAction.reveal.chord)
                == .reveal(secret.id))
    }

    /// Every chord is drawn in the ⋯ menu, which is the only place a keyboard user could learn it.
    @Test("a chord is written the way the menu shows it")
    func chordsReadAsTheyAreTyped() {
        #expect(PanelRowAction.reveal.chord.label == "⌘R")
        #expect(PanelRowAction.copy.chord.label == "⌘⇧C")
        #expect(PanelRowAction.delete.chord.label == "⌘⇧⌫")
    }

    @Test("the shortcut guide covers every row action")
    func shortcutGuideCoversActions() {
        let globalEntries = PanelShortcutCatalog.entries.prefix(10)
        #expect(
            globalEntries.map(\.title) == [
                "Move selection", "Move farther", "Paste selected clip or save",
                "Paste without formatting", "Undo the last deletion",
                "Clear search; close sheet, panel, or guide", "Choose a collection",
                "Rename collection", "Delete collection", "Show this guide",
            ])
        #expect(
            globalEntries.map(\.chord) == [
                "↑ / ↓", "Page Up / Page Down / Home / End", "Return", "⌘ Return", "⌘ Z", "Esc",
                "⌘ 1–9", "⇧ ⌘ R", "⇧ ⌘ Delete", "? (empty search) / ⌘ /",
            ])
        let rowEntries = PanelShortcutCatalog.entries.suffix(PanelRowAction.allCases.count)
        #expect(rowEntries.map(\.chord) == PanelRowAction.allCases.map(\.chord.label))
    }
}

@Suite("The panel's long moves through the list")
struct PanelJumpTests {
    /// Twelve rows, so a page move lands somewhere that is neither end.
    private static let many = (1...12).map { PanelFixture.clip("Clip \($0)", minutesAgo: $0) }

    private func panel() -> PanelSnapshot {
        var snapshot = PanelFixture.panel(Self.many)
        snapshot.selection = Self.many.first?.id
        return snapshot
    }

    @Test("Page Down moves a screenful, and Page Up brings it back")
    func pagesThroughTheList() {
        let down = panel().applying(.jump(.pageDown)).state
        #expect(down.selection == Self.many[PanelSnapshot.rowsPerPage].id)

        let back = down.applying(.jump(.pageUp)).state
        #expect(back.selection == Self.many.first?.id)
    }

    /// ↑↓ stop at the ends rather than wrapping, and so does a page that would overshoot.
    @Test("a page that would run off the end stops at the end")
    func pageStopsAtTheEnds() {
        let bottom = panel().applying([.jump(.pageDown), .jump(.pageDown)]).state
        #expect(bottom.selection == Self.many.last?.id)

        let top = bottom.applying([.jump(.pageUp), .jump(.pageUp)]).state
        #expect(top.selection == Self.many.first?.id)
    }

    @Test("End reaches the last row and Home the first, whatever the list's length")
    func reachesBothEnds() {
        let end = panel().applying(.jump(.bottom)).state
        #expect(end.selection == Self.many.last?.id)

        let home = end.applying(.jump(.top)).state
        #expect(home.selection == Self.many.first?.id)
    }

    /// A sheet asking about one row holds the list still, exactly as ↑↓ are held still.
    @Test("a sheet with nothing to type into holds a jump as it holds an arrow")
    func aSheetHoldsAJump() {
        var asking = panel()
        asking.sheet = .confirmingDelete(Self.many[0].id)

        #expect(asking.applying(.jump(.bottom)).state.selection == asking.selection)
    }

    @Test("a jump in an empty list does nothing")
    func emptyListDoesNothing() {
        let empty = PanelFixture.panel([])

        #expect(empty.applying(.jump(.bottom)).state.selection == empty.selection)
    }
}
