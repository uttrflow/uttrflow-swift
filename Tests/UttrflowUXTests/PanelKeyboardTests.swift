// Tests for the panel's keys: the product loop, where the arrows stop, the selection, ⌘-numbers, reveal.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

@Suite("The quick panel: open, down, down, Return")
struct PanelProductLoopTests {
    /// The whole product written as the gesture; if this needs a paragraph to explain, the model is wrong.
    @Test("↓ ↓ Return inserts the third clip")
    func theWholeProduct() {
        let panel = PanelFixture.panel()

        #expect(panel.applying([.down, .down, .return]).outcome == .insert(PanelFixture.clips[2]))
    }

    @Test("Return on its own inserts the newest clip")
    func returnAlone() {
        #expect(PanelFixture.panel().applying(.return).outcome == .insert(PanelFixture.clips[0]))
    }

    /// The outcome carries the clip, not the row's line, or a multi-line paste is silently cut to line one.
    @Test("Return carries every line of the clip, not the one line the row draws")
    func insertsTheWholeClipNotItsSummary() {
        let many = PanelFixture.clip("first line\nsecond line\nthird line", minutesAgo: 1)

        let outcome = PanelFixture.panel([many]).applying(.return).outcome

        guard case .insert(let chosen) = outcome else {
            Issue.record("Return did not choose a clip")
            return
        }
        #expect(chosen.text == "first line\nsecond line\nthird line")
        // And the row really does draw only the first, so the two are not trivially equal.
        #expect(chosen.summary == "first line")
    }

    @Test("search first, then ↓ ↓ Return — the third of what is left")
    func searchThenArrows() {
        let clips = [
            PanelFixture.clip("staging url", minutesAgo: 1),
            PanelFixture.clip("prod database", minutesAgo: 2),
            PanelFixture.clip("prod api endpoint", minutesAgo: 3),
            PanelFixture.clip("lunch order", minutesAgo: 4),
            PanelFixture.clip("prod bastion", minutesAgo: 5),
        ]

        let response = PanelFixture.panel(clips).applying([.search("prod"), .down, .down, .return])

        #expect(response.outcome == .insert(clips[4]), "the third of the three that matched")
    }

    /// The promise the alias exists for: type the name, press Return, get that clip, without looking.
    @Test("type an alias and press Return, and it is that clip")
    func aliasThenReturn() {
        let clips = [
            PanelFixture.clip("newer, and mentions pgprod", minutesAgo: 1),
            PanelFixture.clip("postgres://prod", minutesAgo: 2, alias: "/pgprod"),
        ]

        #expect(
            PanelFixture.panel(clips).applying([.search("pgprod"), .return]).outcome
                == .insert(clips[1]))
        #expect(
            PanelFixture.panel(clips).applying([.search("/pgprod"), .return]).outcome
                == .insert(clips[1]), "with the slash the convention prints, or without it")
    }

    @Test("a click on a row is Return on that row")
    func clicking() {
        let panel = PanelFixture.panel()
        let response = panel.applying(.choose(PanelFixture.clips[2].id))

        #expect(response.outcome == .insert(PanelFixture.clips[2]))
        #expect(response.state.selection == PanelFixture.clips[2].id, "and it lands there too")
        #expect(response.outcome == panel.applying([.down, .down, .return]).outcome)
    }

    /// Cannot happen from the drawn panel, and the model still has to be total.
    @Test("a click on a row that is not listed does nothing")
    func clickingSomethingElse() {
        let response = PanelFixture.panel().applying(.choose(PanelFixture.clip("elsewhere").id))

        #expect(response.outcome == .open)
        #expect(response.state == PanelFixture.panel())
    }

    @Test("esc closes with nothing chosen")
    func escaping() {
        let response = PanelFixture.panel().applying([.search("prod"), .escape])

        #expect(response.outcome == .dismissed)
        #expect(response.state.query == "prod", "and takes nothing back from the app")
    }

    /// A panel that has closed cannot be typed into, so a run of keys stops where it stopped for the user.
    @Test("keys after the panel closes are not applied")
    func afterClosing() {
        let response = PanelFixture.panel().applying([.return, .down, .down])

        #expect(response.outcome == .insert(PanelFixture.clips[0]))
    }

    @Test("no keys at all leaves the panel exactly as it was")
    func nothingPressed() {
        let response = PanelFixture.panel().applying([])

        #expect(response.outcome == .open)
        #expect(response.state == PanelFixture.panel())
    }
}

@Suite("The quick panel: where the arrows stop")
struct PanelArrowTests {
    /// Stopping rather than wrapping: holding ↓ too long must not silently move the aim to the top.
    @Test("↓ past the bottom stays on the bottom")
    func stopsAtTheBottom() {
        let response = PanelFixture.panel().applying([.down, .down, .down, .down, .down, .return])

        #expect(response.outcome == .insert(PanelFixture.clips[2]))
    }

    @Test("↑ past the top stays on the top")
    func stopsAtTheTop() {
        let response = PanelFixture.panel().applying([.down, .up, .up, .up, .return])

        #expect(response.outcome == .insert(PanelFixture.clips[0]))
    }

    @Test("↑ walks back up the list one row at a time")
    func walksBack() {
        let response = PanelFixture.panel().applying([.down, .down, .up, .return])

        #expect(response.outcome == .insert(PanelFixture.clips[1]))
    }

    @Test("the arrows do nothing to an empty list, and Return does nothing either")
    func emptyList() {
        let panel = PanelFixture.panel([])
        let response = panel.applying([.down, .up, .return])

        #expect(response.outcome == .open)
        #expect(response.state == panel)
    }

    /// A search matching nothing must not close the panel, or the user loses what they typed.
    @Test("Return on a search that matches nothing keeps the panel open")
    func returnOnNoMatches() {
        #expect(PanelFixture.panel().applying([.search("zzz"), .return]).outcome == .open)
    }
}

@Suite("The quick panel: where the selection lands")
struct PanelSelectionTests {
    @Test("a re-render with the same clips keeps the selection")
    func survivesReRender() {
        var panel = PanelFixture.panel().applying([.down, .down]).state
        panel.clips = PanelFixture.clips
        panel.now = PanelFixture.now.addingTimeInterval(30)

        #expect(panel.applying(.return).outcome == .insert(PanelFixture.clips[2]))
    }

    /// The selection is held by identity, so a clip copied while the panel is open does not move it.
    @Test("a clip copied while the panel is open does not move the selection")
    func newClipArrives() {
        var panel = PanelFixture.panel().applying([.down, .down]).state
        panel.clips = [PanelFixture.clip("just copied")] + PanelFixture.clips

        #expect(panel.applying(.return).outcome == .insert(PanelFixture.clips[2]))
    }

    @Test("a selection whose clip has gone falls back to the top")
    func selectedClipRemoved() {
        var panel = PanelFixture.panel().applying([.down, .down]).state
        panel.clips = Array(PanelFixture.clips.prefix(2))

        #expect(panel.applying(.return).outcome == .insert(PanelFixture.clips[0]))
    }

    @Test("typing puts the selection back at the top of what is left")
    func typingResets() {
        let clips = [
            PanelFixture.clip("alpha one", minutesAgo: 1),
            PanelFixture.clip("alpha two", minutesAgo: 2),
            PanelFixture.clip("beta three", minutesAgo: 3),
        ]

        let response = PanelFixture.panel(clips).applying([.down, .down, .search("alpha"), .return])

        #expect(response.outcome == .insert(clips[0]), "not the row two down from before")
    }

    @Test("changing tab puts the selection back at the top")
    func filteringResets() {
        let clips = [
            PanelFixture.clip("a note", minutesAgo: 1),
            PanelFixture.clip("https://one", kind: .link, minutesAgo: 2),
            PanelFixture.clip("https://two", kind: .link, minutesAgo: 3),
        ]

        let response = PanelFixture.panel(clips).applying([.down, .down, .filter(.links), .return])

        #expect(response.outcome == .insert(clips[1]))
    }
}

@Suite("The quick panel: jumping to a collection")
struct PanelCategoryKeyTests {
    /// One loose clip and two filed ones.
    static let clips = [
        PanelFixture.clip("a note", minutesAgo: 1),
        PanelFixture.clip("prod dsn", minutesAgo: 2, category: "Prod"),
        PanelFixture.clip("home address", minutesAgo: 3, category: "Personal"),
    ]

    @Test("⌘2 shows the first collection, ⌘3 the second")
    func jumps() {
        let panel = PanelFixture.panel(Self.clips)

        #expect(panel.applying(.category(number: 2)).state.category == "Prod")
        #expect(panel.applying(.category(number: 3)).state.category == "Personal")
        #expect(panel.applying([.category(number: 3), .return]).outcome == .insert(Self.clips[2]))
    }

    /// The way back needs a key of its own, or the mouse is the only way out of a collection.
    @Test("⌘1 shows everything again")
    func backToAll() {
        let panel = PanelFixture.panel(Self.clips).applying(.category(number: 2)).state

        #expect(panel.applying(.category(number: 1)).state.category == nil)
    }

    @Test("a number nothing is filed under does nothing at all")
    func outOfRange() {
        let panel = PanelFixture.panel(Self.clips)

        #expect(panel.applying(.category(number: 4)).state == panel)
        #expect(panel.applying(.category(number: 0)).state == panel)
    }

    /// There is no ⌘10, but that is about the keyboard; only a number with no collection is refused.
    @Test("a collection past the ninth can still be jumped to, but a missing one cannot")
    func pastTheNinth() {
        let clips = (1...12).map { PanelFixture.clip("c\($0)", minutesAgo: $0, category: "C\($0)") }
        let panel = PanelFixture.panel(clips)

        #expect(panel.applying(.category(number: 9)).state.category == "C8")
        #expect(panel.applying(.category(number: 10)).state.category == "C9")
        #expect(panel.applying(.category(number: 13)).state.category == "C12")
        #expect(panel.applying(.category(number: 14)).state == panel, "there is no thirteenth")
    }

    @Test("jumping to a collection puts the selection back at the top")
    func jumpingResets() {
        let clips = [
            PanelFixture.clip("one", minutesAgo: 1, category: "Prod"),
            PanelFixture.clip("two", minutesAgo: 2, category: "Prod"),
        ]
        let panel = PanelFixture.panel(clips)

        #expect(panel.applying([.down, .category(number: 2), .return]).outcome == .insert(clips[0]))
    }
}

@Suite("The quick panel: revealing a secret")
struct PanelRevealTests {
    @Test("revealing is a key of its own, and touches only that clip")
    func revealing() {
        let secret = PanelFixture.clip("sk-live-1234", kind: .secret)
        let other = PanelFixture.clip("sk-live-9999", kind: .secret, minutesAgo: 1)
        let panel = PanelFixture.panel([secret, other]).applying(.reveal(secret.id)).state

        #expect(panel.revealed == [secret.id])
    }

    /// Arrowing over a secret must not unmask it; the panel is opened in meetings.
    @Test("arrowing onto a secret does not reveal it")
    func arrowingDoesNotReveal() {
        let secret = PanelFixture.clip("sk-live-1234", kind: .secret, minutesAgo: 1)
        let panel = PanelFixture.panel([PanelFixture.clip(), secret])

        #expect(panel.applying(.down).state.revealed.isEmpty)
    }
}
