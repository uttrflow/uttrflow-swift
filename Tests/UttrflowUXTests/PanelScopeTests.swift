import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// The bottom bar. Every button in it used to be decoration: three drawn disabled and the
/// fourth wired to an empty closure, in the most reachable strip of the whole panel.
@Suite("The bottom bar")
struct PanelScopeTests {
    static let clips = [
        PanelFixture.clip("kept and filed", minutesAgo: 1, category: "Work", isPinned: true),
        PanelFixture.clip("just kept", minutesAgo: 2, isPinned: true),
        PanelFixture.clip("just filed", minutesAgo: 3, category: "Work"),
        PanelFixture.clip("neither", minutesAgo: 4),
    ]

    static func rows(
        _ scope: PanelScope, clips: [Clip] = PanelScopeTests.clips, query: String = ""
    ) -> [String] {
        var snapshot = PanelFixture.panel(clips, query: query)
        snapshot.scope = scope
        return PanelPresenter.present(snapshot).rows.map(\.summary)
    }

    /// History is what you copied and have not put anywhere. A pin is somewhere to put
    /// one: the clip moves to the Pinned tab rather than appearing in both, which made the
    /// Pinned tab a second copy of the list and quietly filled History with things the
    /// user had already filed away.
    @Test("History is what you copied and have not put anywhere")
    func history() {
        #expect(Self.rows(.history) == ["neither"])
    }

    /// The chips and the bottom bar combine rather than override, and a collection chip
    /// is the one narrowing that has to *lift* the arrivals rule instead of adding to it:
    /// History shows what was put nowhere, the chip asks for what was put in a collection,
    /// and without this no clip is ever both.
    @Test("but choosing a collection shows what is filed there")
    func aCollectionChipLiftsTheArrivalsRule() {
        var snapshot = PanelFixture.panel(Self.clips, category: "Work")
        snapshot.scope = .history

        #expect(PanelPresenter.present(snapshot).rows.map(\.summary) == ["just filed"])
    }

    /// A pin moves a clip; it does not copy it. Showing a pinned clip in both places made
    /// the Pinned tab a second view of the same list, and meant the longer the panel was
    /// used the more of History was things the user had already put away.
    @Test("a pinned clip is in Pinned and nowhere else it used to be")
    func pinningMovesRatherThanCopies() {
        let clips = [
            PanelFixture.clip("a pinned copy", minutesAgo: 1, isPinned: true),
            PanelFixture.clip("an ordinary copy", minutesAgo: 2),
            PanelFixture.clip(
                "a pinned dictation", minutesAgo: 3, isPinned: true, origin: .uttrflow),
            PanelFixture.clip("an ordinary dictation", minutesAgo: 4, origin: .uttrflow),
        ]

        #expect(Self.rows(.history, clips: clips) == ["an ordinary copy"])
        #expect(Self.rows(.uttrflow, clips: clips) == ["an ordinary dictation"])
        #expect(Self.rows(.pinned, clips: clips) == ["a pinned copy", "a pinned dictation"])
    }

    /// Moving it out of History must not put it out of reach. A search looks everywhere by
    /// design, and that is what stops the move being a disappearance.
    @Test("but a search still finds it")
    func aSearchStillFindsAPinnedClip() {
        let clips = [
            PanelFixture.clip("the pinned one", minutesAgo: 1, isPinned: true),
            PanelFixture.clip("an ordinary one", minutesAgo: 2),
        ]

        #expect(Self.rows(.history, clips: clips, query: "pinned") == ["the pinned one"])
    }

    /// The row draws `pin.fill` on a pinned clip. The tab drew a star for the same idea,
    /// so the panel had two glyphs for one thing and neither taught the other — and a star
    /// means "favourite", which is a judgement about a clip, where a pin is a place.
    @Test("and the tab wears the mark the row wears")
    func theTabIsAPin() {
        #expect(PanelScope.pinned.glyph == .symbol("pin"))
        #expect(
            PanelPresenter.tabs(for: PanelFixture.panel())
                .first { $0.title == "Pinned" }?.glyph == .symbol("pin"))
    }

    @Test("Pinned is only what was kept")
    func pinned() {
        #expect(Self.rows(.pinned) == ["kept and filed", "just kept"])
    }

    @Test("Collections is only what was filed")
    func collections() {
        #expect(Self.rows(.collections) == ["kept and filed", "just filed"])
    }

    /// A different axis from the kind filter, so the two narrow together rather than one
    /// replacing the other. Pinned and Images is "the pictures worth keeping", which is a
    /// question somebody actually has.
    @Test("the bar and the kind filter combine rather than override")
    func combinesWithTheFilter() {
        var snapshot = PanelFixture.panel([
            PanelFixture.clip("https://example.com", kind: .link, minutesAgo: 1, isPinned: true),
            PanelFixture.clip("plain words", minutesAgo: 2, isPinned: true),
            PanelFixture.clip("https://elsewhere.com", kind: .link, minutesAgo: 3),
        ])
        snapshot.scope = .pinned
        snapshot.filter = .links

        let shown = PanelPresenter.present(snapshot).rows.map(\.summary)

        #expect(shown == ["https://example.com"])
    }

    /// The same rule the collection chips already follow, for the same reason: somebody
    /// searching for a clip does not remember whether they pinned it, so a search inside
    /// Pinned answers "not here", which is the one answer they cannot act on.
    @Test("a search looks everywhere, whatever the bar is showing")
    func searchingLeavesTheBarBehind() {
        #expect(Self.rows(.pinned, query: "neither") == ["neither"])
    }

    @Test("and the bar comes back when the search is cleared")
    func clearingRestoresIt() {
        #expect(Self.rows(.pinned, query: "") == ["kept and filed", "just kept"])
    }

    // MARK: - What the bar draws

    @Test("every button carries something to do")
    func nothingIsDecoration() {
        let tabs = PanelPresenter.present(PanelFixture.panel(Self.clips)).tabs

        #expect(tabs.count == PanelScope.allCases.count + 1)
        #expect(
            tabs.map(\.title) == [
                "History", "From Uttrflow", "Pinned", "Collections", "Settings",
            ])
        #expect(tabs.last?.intent == .openSettings)
        for tab in tabs {
            // A glyph that names nothing draws nothing, and a blank button in the most
            // reachable strip of the panel is the decoration this test exists to refuse.
            if case .symbol(let name) = tab.glyph { #expect(!name.isEmpty) }
        }
        #expect(
            tabs.filter { $0.glyph == .brandMark }.map(\.title) == ["From Uttrflow"],
            "the mark says which tab is Uttrflow's own, and only that one")
    }

    /// Exactly one, and never Settings — that is a door out of the panel rather than a
    /// place the list can be, and drawing it lit would say the panel was somewhere it
    /// cannot be.
    @Test("exactly one is on, and it is never Settings")
    func oneIsOn() {
        for scope in PanelScope.allCases {
            var snapshot = PanelFixture.panel(Self.clips)
            snapshot.scope = scope
            let tabs = PanelPresenter.present(snapshot).tabs

            #expect(tabs.filter(\.isActive).count == 1)
            #expect(tabs.first { $0.isActive }?.title == scope.title)
            #expect(tabs.last?.isActive == false)
        }
    }

    @Test("pressing one is the model's own work, so it carries a key")
    func scopeIsAKey() {
        #expect(PanelIntent.scope(.pinned).key == .scope(.pinned))
        #expect(PanelIntent.openSettings.key == nil, "only the app can open a window")
    }

    @Test("and applying that key changes what is shown")
    func applyingTheKey() {
        let panel = PanelFixture.panel(Self.clips)

        let response = panel.applying(.scope(.pinned))

        #expect(response.outcome == .open)
        #expect(response.state.scope == .pinned)
        #expect(PanelPresenter.present(response.state).rows.count == 2)
    }

    // MARK: - Nothing to show

    /// An empty Pinned tab over a full clipboard is not an empty clipboard. Telling
    /// somebody who has copied three hundred things that whatever they copy will turn up
    /// here reads as the app having lost them.
    @Test("an empty Pinned tab says nothing is pinned, not that nothing was copied")
    func emptyPinned() {
        var snapshot = PanelFixture.panel([PanelFixture.clip("something", minutesAgo: 1)])
        snapshot.scope = .pinned

        let empty = PanelPresenter.present(snapshot).emptyState

        #expect(empty?.title == "Nothing pinned")
        #expect(empty?.message.contains("Pin a clip") == true)
    }

    @Test("and an empty Collections tab says nothing is filed")
    func emptyCollections() {
        var snapshot = PanelFixture.panel([PanelFixture.clip("something", minutesAgo: 1)])
        snapshot.scope = .collections

        #expect(PanelPresenter.present(snapshot).emptyState?.title == "Nothing filed")
    }

    /// The genuinely empty clipboard still says so, whichever tab is open — there is
    /// nothing to pin or file either.
    @Test("but an empty clipboard still says nothing was copied")
    func trulyEmpty() {
        var snapshot = PanelFixture.panel([])
        snapshot.scope = .pinned

        #expect(PanelPresenter.present(snapshot).emptyState?.title == "Nothing copied yet")
    }

    /// A search that found nothing is about the search, not about the tab.
    @Test("and a search that finds nothing says so rather than blaming the tab")
    func searchBeatsTheTab() {
        var snapshot = PanelFixture.panel(Self.clips, query: "nothing matches this")
        snapshot.scope = .pinned

        #expect(PanelPresenter.present(snapshot).emptyState?.title == "No matches")
    }
}

/// Two questions the panel has to answer the same way every time: how many collections
/// can be on at once, and whether an empty list explains itself honestly.
@Suite("One collection at a time, and an empty list that tells the truth")
struct PanelNarrowingTests {
    static let clips = [
        PanelFixture.clip("in db", minutesAgo: 1, category: "db"),
        PanelFixture.clip("in personal", minutesAgo: 2, category: "personal"),
        PanelFixture.clip("filed nowhere", minutesAgo: 3),
    ]

    /// Reported as a suspected invalid state: two collection chips looking chosen at
    /// once. It cannot happen — the snapshot holds one optional name, and a chip is on
    /// when it equals that name — and this says so for every collection and every
    /// choice, so it stays impossible rather than merely being impossible today.
    @Test("never more than one collection chip is on, whichever is chosen")
    func atMostOneCollectionIsOn() {
        for chosen in [nil, "db", "personal", "missing"] {
            let page = PanelFixture.page(Self.clips, category: chosen)
            let on = page.categories.filter(\.isActive)

            #expect(on.count <= 1, "\(on.count) collections on for \(chosen ?? "none")")
            if let chosen, chosen != "missing" {
                #expect(on.first?.title == chosen)
            } else {
                #expect(on.isEmpty)
            }
        }
    }

    /// One chip at a time across the whole row, kinds and collections together.
    ///
    /// They are different questions, and combining them answers a real one — "the
    /// pictures in db". But a row of chips reads as one set whatever divider is drawn in
    /// it, and two of them lit looked like a bug to everyone who saw it. Choosing either
    /// clears the other, and this walks every reachable pair of presses to say so.
    @Test("exactly one chip in the row is on, whatever is pressed")
    func oneChipAtATime() {
        for first in Self.everyChipPress() {
            for second in Self.everyChipPress() {
                let state = PanelFixture.panel(Self.clips).applying([first, second]).state
                let page = PanelPresenter.present(state)
                let on =
                    page.filters.filter(\.isActive).map(\.title)
                    + page.categories.filter(\.isActive).map(\.title)

                #expect(on.count == 1, "\(on) on after \(first) then \(second)")
            }
        }
    }

    /// Every press the chip row can send: each kind, and each collection by its number.
    static func everyChipPress() -> [PanelKey] {
        PanelFilter.allCases.map { PanelKey.filter($0) }
            + (1...3).map { PanelKey.category(number: $0) }
    }

    @Test("choosing a kind lets go of the collection")
    func aKindClearsTheCollection() {
        let inDB = PanelFixture.panel(Self.clips).applying(.category(number: 2)).state
        #expect(inDB.category == "db")

        let then = inDB.applying(.filter(.links)).state

        #expect(then.filter == .links)
        #expect(then.category == nil)
    }

    @Test("and choosing a collection lets go of the kind")
    func aCollectionClearsTheKind() {
        let links = PanelFixture.panel(Self.clips).applying(.filter(.links)).state

        let then = links.applying(.category(number: 2)).state

        #expect(then.category == "db")
        #expect(then.filter == .all)
    }

    /// ⌘1 is "show me everything", so it has to let go of both. Clearing only the
    /// collection would leave a kind filter on under a row that says All.
    @Test("and everything means everything")
    func everythingClearsBoth() {
        let narrowed = PanelFixture.panel(Self.clips)
            .applying([.filter(.links), .category(number: 2)]).state

        let then = narrowed.applying(.category(number: 1)).state

        #expect(then.category == nil)
        #expect(then.filter == .all)
    }

    /// A search spans every collection, so no collection is drawn as chosen — and the
    /// kind chip comes back on, because the kind really is still narrowing the results.
    @Test("while searching the kind is the chip that is on, because it is the one applied")
    func searchingHandsTheRowBackToTheKind() {
        let searching = PanelFixture.panel(Self.clips)
            .applying([.filter(.links), .search("in")]).state
        let page = PanelPresenter.present(searching)

        #expect(page.categories.allSatisfy { !$0.isActive })
        #expect(page.filters.filter(\.isActive).map(\.title) == ["Links"])
    }

    // MARK: - What an empty list says

    static func empty(
        scope: PanelScope = .history, filter: PanelFilter = .all, category: String? = nil
    ) -> MainEmptyState? {
        var snapshot = PanelFixture.panel(Self.clips, filter: filter, category: category)
        snapshot.scope = scope
        return PanelPresenter.present(snapshot).emptyState
    }

    /// The case that was reported: a collection with clips in it, a kind filter hiding
    /// all of them, and a sentence that named only the collection.
    @Test("a kind and a collection are both named")
    func kindAndCollection() {
        let empty = Self.empty(filter: .images, category: "db")

        #expect(empty?.title == "No Images in db")
        #expect(empty?.message == "Nothing filed in db is an image.")
    }

    @Test("a kind and the pinned tab are both named")
    func kindAndPinned() {
        let empty = Self.empty(scope: .pinned, filter: .code)

        #expect(empty?.title == "No Code pinned")
        #expect(empty?.message == "Nothing you have pinned is code.")
    }

    @Test("a kind and the collections tab are both named")
    func kindAndFiled() {
        let empty = Self.empty(scope: .collections, filter: .code)

        #expect(empty?.title == "No Code filed")
        #expect(empty?.message == "Nothing you have filed is code.")
    }

    @Test("the pinned tab inside a collection names both")
    func pinnedInsideACollection() {
        let empty = Self.empty(scope: .pinned, category: "db")

        #expect(empty?.title == "Nothing pinned in db")
        #expect(empty?.message == "Nothing filed in db is pinned.")
    }

    /// Every combination has to produce a sentence, and none of them may end up saying
    /// nothing was copied over a clipboard that has clips in it.
    @Test("every combination says something, and none of them claims the clipboard is empty")
    func everyCombinationIsAnswerable() {
        for scope in PanelScope.allCases {
            for filter in PanelFilter.allCases {
                for category in [nil, "db", "personal"] {
                    let empty = Self.empty(scope: scope, filter: filter, category: category)
                    guard let empty else { continue }

                    #expect(!empty.title.isEmpty)
                    #expect(empty.message.hasSuffix("."))
                    #expect(empty.title != "Nothing copied yet")
                }
            }
        }
    }
}
