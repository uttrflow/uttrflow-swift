import Testing

@testable import UttrflowUX

@Suite("Panel key decisions")
struct PanelKeyDecisionTests {
    private let presentation = PanelFixture.page([])

    @Test("command-Z undoes the last delete")
    func commandZ() {
        #expect(decision("z", command: true) == .intent(.undoDelete))
    }

    @Test("command-Return chooses without formatting")
    func commandReturn() {
        #expect(decision("", command: true, isReturn: true) == .key(.returnPlain))
        #expect(
            decision("", command: true, isReturn: true, menuOpen: true) == .keyAfterClosingMenu(.returnPlain))
        #expect(decision("", isReturn: true) == .key(.return))
    }

    @Test("command-1 and command-9 choose their numbered collections")
    func commandDigits() {
        #expect(decision("1", command: true) == .key(.category(number: 1)))
        #expect(decision("9", command: true) == .key(.category(number: 9)))
    }

    @Test("command-0 and command-C stay with the search field")
    func unclaimedCommandKeys() {
        #expect(decision("0", command: true) == .ignore)
        #expect(decision("c", command: true) == .ignore)
    }

    @Test("Escape closes an open menu before the panel")
    func escapeWithMenu() {
        #expect(decision("", isEscape: true, menuOpen: true) == .closeMenu)
        #expect(PanelKeyHandling.relayDecision(for: .escape, rowMenuOpen: true) == .closeMenu)
    }

    @Test("Escape reaches the panel when no menu is open")
    func escapeWithoutMenu() {
        #expect(decision("", isEscape: true) == .key(.escape))
        #expect(
            PanelKeyHandling.relayDecision(for: .escape, rowMenuOpen: false, query: "needle")
                == .key(.clearSearch))
        #expect(
            PanelKeyHandling.relayDecision(
                for: .escape, rowMenuOpen: false, query: "needle", hasSheet: true)
                == .key(.escape))
        #expect(PanelKeyHandling.relayDecision(for: .escape, rowMenuOpen: false) == .key(.escape))
    }

    @Test("command-slash opens the shortcut guide")
    func shortcutGuideChord() {
        #expect(decision("/", command: true) == .key(.showShortcuts))
        #expect(decision("?", shift: true) == .key(.showShortcuts))
        let searching = PanelPresenter.present(PanelFixture.panel([], query: "needle"))
        #expect(
            PanelKeyHandling.decision(
                characters: "?", commandHeld: false, shiftHeld: true,
                isReturn: false, isEscape: false, rowMenuOpen: false, presentation: searching)
                == .ignore)
    }

    @Test("a non-command character stays with the search field")
    func nonCommandCharacter() {
        #expect(decision("a") == .ignore)
    }

    @Test("a relayed non-Escape key closes the menu and still reaches the panel")
    func relayClosesMenuBeforeKey() {
        #expect(
            PanelKeyHandling.relayDecision(for: .return, rowMenuOpen: true)
                == .keyAfterClosingMenu(.return))
        #expect(PanelKeyHandling.relayDecision(for: .return, rowMenuOpen: false) == .key(.return))
    }

    @Test("a command row chord still uses the highlighted row's action")
    func commandRowAction() {
        let clip = PanelFixture.clip("Hello there")
        var snapshot = PanelFixture.panel([clip])
        snapshot.selection = clip.id
        let page = PanelPresenter.present(snapshot)

        let choice = PanelKeyHandling.decision(
            characters: "n", commandHeld: true, shiftHeld: false,
            isReturn: false, isEscape: false, rowMenuOpen: false, presentation: page)
        #expect(choice == .intent(.alias(clip.id)))

        let copy = PanelKeyHandling.decision(
            characters: "c", commandHeld: true, shiftHeld: true,
            isReturn: false, isEscape: false, rowMenuOpen: false, presentation: page)
        #expect(copy == .intent(.copy(clip.id)))
    }

    @Test("AppKit Backspace character resolves the selected row's delete action")
    func appKitBackspaceDeletesSelectedRow() {
        let clip = PanelFixture.clip("Hello there")
        var snapshot = PanelFixture.panel([clip])
        snapshot.selection = clip.id
        let page = PanelPresenter.present(snapshot)

        #expect(
            PanelKeyHandling.decision(
                characters: "\u{7F}", commandHeld: true, shiftHeld: true,
                isReturn: false, isEscape: false, rowMenuOpen: false, presentation: page)
                == .intent(.delete(clip.id)))
    }

    @Test("row chords are ignored while either typing sheet is open")
    func rowChordsAreIgnoredByTypingSheets() {
        let clip = PanelFixture.clip("Hello there")
        for sheet in [
            PanelSheet.aliasing(clip.id, draft: "draft"),
            .moving(clip.id, draft: "draft"),
        ] {
            var snapshot = PanelFixture.panel([clip])
            snapshot.selection = clip.id
            snapshot.sheet = sheet
            let page = PanelPresenter.present(snapshot)

            for chord in [PanelRowAction.alias, .move, .delete, .pin, .copy] {
                #expect(
                    PanelKeyHandling.decision(
                        characters: String(chord.chord.character),
                        commandHeld: true,
                        shiftHeld: chord.chord.isShifted,
                        isReturn: false,
                        isEscape: false,
                        rowMenuOpen: false,
                        presentation: page) == .ignore)
            }
            #expect(
                PanelKeyHandling.decision(
                    characters: "", commandHeld: false, shiftHeld: false,
                    isReturn: true, isEscape: false, rowMenuOpen: false,
                    presentation: page) == .key(.return))
            #expect(
                PanelKeyHandling.decision(
                    characters: "", commandHeld: false, shiftHeld: false,
                    isReturn: false, isEscape: true, rowMenuOpen: false,
                    presentation: page) == .key(.escape))
            #expect(
                PanelKeyHandling.decision(
                    characters: "", commandHeld: true, shiftHeld: false,
                    isReturn: true, isEscape: false, rowMenuOpen: false,
                    presentation: page) == .ignore)
        }
    }

    private func decision(
        _ characters: String,
        command: Bool = false,
        shift: Bool = false,
        isReturn: Bool = false,
        isEscape: Bool = false,
        menuOpen: Bool = false
    ) -> PanelKeyDecision {
        PanelKeyHandling.decision(
            characters: characters,
            commandHeld: command,
            shiftHeld: shift,
            isReturn: isReturn,
            isEscape: isEscape,
            rowMenuOpen: menuOpen,
            presentation: presentation)
    }
}
