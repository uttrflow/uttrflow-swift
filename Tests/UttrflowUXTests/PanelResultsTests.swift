// Tests for which clips the panel lists: filtering, searching, ordering, and search scope.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

@Suite("The quick panel: which clips are listed")
struct PanelFilteringTests {
    /// One clip of every kind.
    static let everything: [Clip] = [
        PanelFixture.clip("a plain note", kind: .text, minutesAgo: 1),
        PanelFixture.clip("https://example.com", kind: .link, minutesAgo: 2),
        PanelFixture.clip("let x = 1", kind: .code, minutesAgo: 3),
        PanelFixture.clip("sk-live-1234", kind: .secret, minutesAgo: 4),
        PanelFixture.clip("#FF8800", kind: .colour, minutesAgo: 5),
        PanelFixture.clip("screenshot.png", kind: .image, minutesAgo: 6),
    ]

    @Test("All shows everything, in the order the store keeps it")
    func all() {
        let rows = PanelFixture.panel(Self.everything).results.rows

        #expect(rows.map(\.clip) == Self.everything)
        #expect(rows.allSatisfy { $0.match == nil }, "nothing was typed, so nothing matched")
    }

    @Test(
        "each tab shows its own kinds",
        arguments: [
            (PanelFilter.text, [ClipKind.text, .secret, .colour]),
            (.links, [.link]),
            (.code, [.code]),
            (.images, [.image]),
        ])
    func tabs(filter: PanelFilter, kinds: [ClipKind]) {
        let rows = PanelFixture.panel(Self.everything, filter: filter).results.rows

        #expect(rows.map(\.clip.kind) == kinds)
    }

    /// A kind no tab admits could only be found by searching, which reads as the app losing it.
    @Test("every kind of clip belongs to exactly one tab besides All")
    func everyKindHasATab() {
        for kind in ClipKind.allCases {
            let tabs = PanelFilter.allCases.filter { $0 != .all && $0.admits(kind) }
            #expect(tabs.count == 1, "\(kind) is admitted by \(tabs)")
        }
        #expect(ClipKind.allCases.allSatisfy { PanelFilter.all.admits($0) })
    }

    @Test("a collection shows only what is filed in it")
    func categories() {
        let clips = [
            PanelFixture.clip("one", minutesAgo: 1, category: "Prod"),
            PanelFixture.clip("two", minutesAgo: 2, category: "Personal"),
            PanelFixture.clip("three", minutesAgo: 3, category: " Prod "),
        ]

        let rows = PanelFixture.panel(clips, category: "Prod").results.rows

        #expect(rows.map(\.clip.text) == ["one", "three"], "however it was spaced when filed")
    }

    /// A collection filed under spaces is no collection, so it cannot hide the list behind a blank chip.
    @Test("a blank collection name shows everything")
    func blankCategory() {
        let panel = PanelFixture.panel(category: "   ")

        #expect(panel.results.rows.count == PanelFixture.clips.count)
        #expect(panel.categories.isEmpty)
    }

    @Test("the collections are the ones clips are filed under, in the order first met")
    func categoryNames() {
        let clips = [
            PanelFixture.clip("one", minutesAgo: 1, category: "Prod"),
            PanelFixture.clip("two", minutesAgo: 2),
            PanelFixture.clip("three", minutesAgo: 3, category: "Personal"),
            PanelFixture.clip("four", minutesAgo: 4, category: "Prod"),
            PanelFixture.clip("five", minutesAgo: 5, category: "  "),
        ]

        #expect(PanelFixture.panel(clips).categories == ["Prod", "Personal"])
    }
}

@Suite("The quick panel: searching")
struct PanelSearchTests {
    /// A clip with an alias, one with plain text, one filed away.
    static let clips: [Clip] = [
        PanelFixture.clip("postgres://user@prod", minutesAgo: 1, alias: "/pgprod"),
        PanelFixture.clip("a note about the database", minutesAgo: 2),
        PanelFixture.clip("an address", minutesAgo: 3, category: "Personal"),
    ]

    /// The results for a query over these clips.
    static func rows(_ query: String) -> [PanelResult] {
        PanelFixture.panel(clips, query: query).results.rows
    }

    /// The three mean different things to the reader, so the row says which, rather than making them look.
    @Test("a hit says whether it was the alias, the collection or the contents")
    func matchFields() {
        #expect(Self.rows("pgpr").map(\.match) == [.alias])
        #expect(Self.rows("Personal").map(\.match) == [.category])
        #expect(Self.rows("database").map(\.match) == [.content])
        #expect(Self.rows("zzz").isEmpty)
    }

    /// Two rows rather than three, because with nothing typed this is History and the third is filed.
    @Test("nothing typed means no match to report")
    func nothingTyped() {
        let rows = Self.rows("   ")

        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.match == nil })
    }

    /// A name the user chose outranks a word that merely happens to be in the text.
    @Test("the strongest place a query is found is the one reported")
    func precedence() {
        let clip = PanelFixture.clip("prod dsn", alias: "/prod", category: "Prod")
        let rows = PanelFixture.panel([clip], query: "prod").results

        #expect(rows.rows.map(\.match) == [.alias])
        #expect(PanelFixture.panel([clip], query: "dsn").results.rows.map(\.match) == [.content])
    }

    @Test("case and accents are the user's problem, not theirs to remember")
    func folding() {
        let clips = [PanelFixture.clip("Café Society"), PanelFixture.clip("BENGALURU", minutesAgo: 1)]

        #expect(PanelFixture.panel(clips, query: "cafe").results.rows.count == 1)
        #expect(PanelFixture.panel(clips, query: "bengaluru").results.rows.count == 1)
    }

    @Test("an alias typed in full sorts to the top and takes the selection")
    func exactAlias() {
        let clips = [
            PanelFixture.clip("pinned, and mentions pgprod", minutesAgo: 1, isPinned: true),
            PanelFixture.clip("postgres://prod", minutesAgo: 2, alias: "/pgprod"),
        ]

        let results = PanelFixture.panel(clips, query: "pgprod").results

        #expect(results.rows.map(\.clip) == [clips[1], clips[0]], "even above a pin")
        #expect(results.rows.map(\.isExactAlias) == [true, false])
        #expect(results.selected == clips[1])
    }

    /// A slash on its own is not a name, so it searches like any other characters.
    @Test("a bare slash is a search, not an alias")
    func bareSlash() {
        let results = PanelFixture.panel(Self.clips, query: "/").results

        #expect(results.rows.map(\.clip.text) == ["postgres://user@prod"])
        #expect(results.rows.map(\.isExactAlias) == [false])
    }

    @Test("a clip with no alias can never be an exact one")
    func noAlias() {
        #expect(PanelFixture.panel(Self.clips, query: "database").results.rows.map(\.isExactAlias) == [false])
    }

    /// Searched like anything else and still masked when drawn: what is learnt is that a clip matches.
    @Test("a secret is searchable by its contents")
    func secretsAreSearchable() {
        let secret = PanelFixture.clip("sk-live-1234", kind: .secret)

        #expect(PanelFixture.panel([secret], query: "sk-live").results.rows.count == 1)
    }
}

@Suite("The quick panel: the order of the list")
struct PanelOrderTests {
    /// Pinned and unpinned meet only in a search or inside a collection, since a pin moves a clip.
    @Test("pinned clips sort above the rest")
    func pinned() {
        let clips = [
            PanelFixture.clip("newest thing", minutesAgo: 1),
            PanelFixture.clip("older thing but pinned", minutesAgo: 2, isPinned: true),
            PanelFixture.clip("oldest thing", minutesAgo: 3),
        ]

        #expect(
            PanelFixture.panel(clips, query: "thing").results.rows.map(\.clip.text)
                == ["older thing but pinned", "newest thing", "oldest thing"])
    }

    /// Inside a collection with a kind filter, the pin still sorts within whatever is left.
    @Test("pinning sorts within the tab that is showing, not across the whole clipboard")
    func pinnedWithinAView() {
        let clips = [
            PanelFixture.clip("a pinned note", minutesAgo: 1, category: "db", isPinned: true),
            PanelFixture.clip("https://one", kind: .link, minutesAgo: 2, category: "db"),
            PanelFixture.clip(
                "https://two", kind: .link, minutesAgo: 3, category: "db", isPinned: true),
        ]
        var snapshot = PanelFixture.panel(clips, filter: .links, category: "db")
        snapshot.scope = .collections

        #expect(snapshot.results.rows.map(\.clip.text) == ["https://two", "https://one"])
    }

    /// Clips of equal rank keep copy order, or counting rows between two draws would be a gamble.
    @Test("clips of equal rank keep the order the store gave them")
    func stable() {
        let clips = (1...20).map { PanelFixture.clip("clip \($0)", minutesAgo: $0) }
        let panel = PanelFixture.panel(clips)

        #expect(panel.results.rows.map(\.clip) == clips)
    }

    @Test("an empty list selects nothing at all")
    func emptySelection() {
        let results = PanelFixture.panel([]).results

        #expect(results.selectedIndex == nil)
        #expect(results.selected == nil)
    }

    @Test("a list that has anything in it always has a row selected")
    func neverNothing() {
        let panel = PanelFixture.panel()

        #expect(panel.results.selectedIndex == 0)
        #expect(panel.applying(.down).state.results.selectedIndex == 1)
    }
}

/// A tab narrows browsing, never searching: a scoped search's empty list reads as "never copied".
@Suite("The quick panel: a search is not confined to the open tab")
struct PanelSearchScopeTests {
    /// Two collections, with "postgres" in both.
    static let clips = [
        PanelFixture.clip("work note", minutesAgo: 1, category: "Work"),
        PanelFixture.clip("postgres connection", minutesAgo: 2, category: "Servers"),
        PanelFixture.clip("postgres notes", minutesAgo: 3, category: "Work"),
    ]

    @Test("typing inside a tab still finds what is filed in the others")
    func searchLeavesTheTab() {
        let panel = PanelFixture.panel(Self.clips, query: "postgres", category: "Work")

        let found = panel.results.rows.map(\.clip.text)

        #expect(found.contains("postgres connection"), "filed under Servers, and still found")
        #expect(found.count == 2)
    }

    @Test("clearing the search puts the user back in the tab they were browsing")
    func clearingRestoresTheTab() {
        let panel = PanelFixture.panel(Self.clips, query: "postgres", category: "Work")

        let cleared = panel.applying(.search("")).state

        #expect(cleared.category == "Work", "the tab was never thrown away")
        #expect(cleared.results.rows.map(\.clip.text) == ["work note", "postgres notes"])
    }

    /// No chip is drawn on while searching, which says the same thing as an All chip would.
    @Test("while searching, no collection is drawn as the one being shown")
    func theChipTellsTheTruth() {
        let searching = PanelFixture.panel(Self.clips, query: "postgres", category: "Work")
        let browsing = PanelFixture.panel(Self.clips, category: "Work")

        let whileSearching = PanelPresenter.present(searching).categories
        let whileBrowsing = PanelPresenter.present(browsing).categories

        #expect(whileSearching.first(where: \.isActive) == nil)
        #expect(!whileSearching.contains { $0.title == "All" })
        #expect(whileBrowsing.first(where: \.isActive)?.title == "Work")
    }
}
