// Tests for search states: grouped results, the cap, match excerpts, no results, and scope.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// A list mixing alias, collection and content hits without saying which makes the user open rows.
@Suite("H1 · results, grouped by where the match was")
struct PanelResultGroupingTests {
    /// One clip matching by alias, one by collection, one by content.
    static let clips = [
        PanelFixture.clip("nothing to do with it", minutesAgo: 1, alias: "prod"),
        PanelFixture.clip("a clip filed away", minutesAgo: 2, category: "prod"),
        PanelFixture.clip("the prod database", minutesAgo: 3),
    ]

    @Test("one group per kind of match, named for what the user did")
    func groupsAreNamed() {
        let page = PanelPresenter.present(PanelFixture.panel(Self.clips, query: "prod"))

        #expect(page.groups.map(\.field) == [.alias, .category, .content])
        #expect(page.groups.map(\.title) == ["Names you gave", "Collections", "Contents"])
    }

    @Test("no groups at all when nothing has been typed")
    func noGroupsWhileBrowsing() {
        #expect(PanelPresenter.present(PanelFixture.panel(Self.clips)).groups.isEmpty)
    }

    /// The arrow keys walk the flat list, so the headings must be assembled in the same order.
    @Test("the groups, laid end to end, are exactly the list the arrows walk")
    func groupsMatchTheKeyboardOrder() {
        let page = PanelPresenter.present(PanelFixture.panel(Self.clips, query: "prod"))

        #expect(page.groups.flatMap(\.rows).map(\.id) == page.rows.map(\.id))
    }

    /// An exact alias is an alias match, so grouping puts it in the first group anyway.
    @Test("grouping does not disturb the promise that an alias comes first")
    func aliasStillWins() {
        let page = PanelPresenter.present(PanelFixture.panel(Self.clips, query: "prod"))

        #expect(page.rows.first?.alias == "prod")
        #expect(page.selectedRow?.alias == "prod")
    }
}

/// A search matching four hundred clips by content must not bury the one matched by name.
@Suite("H6 · very many results")
struct PanelResultCapTests {
    /// Twenty clips that all match by content.
    static let many = (1...20).map { PanelFixture.clip("prod server \($0)", minutesAgo: $0) }

    @Test("each kind of match is capped, and says how many it left out")
    func cappedAndCounted() {
        let page = PanelPresenter.present(PanelFixture.panel(Self.many, query: "prod"))

        #expect(page.rows.count == PanelPresenter.rowsPerGroup)
        #expect(page.groups.first?.more == 20 - PanelPresenter.rowsPerGroup)
    }

    /// A capped list that does not admit it is a list the user reads as complete.
    @Test("nothing is left out silently")
    func theCountIsHonest() {
        let page = PanelPresenter.present(PanelFixture.panel(Self.many, query: "prod"))
        let drawn = page.groups.reduce(0) { $0 + $1.rows.count }
        let hidden = page.groups.reduce(0) { $0 + $1.more }

        #expect(drawn + hidden == 20, "every match is either drawn or counted")
    }

    /// Browsing is not searching: the cap makes a result set readable, not the history shorter.
    @Test("browsing is never capped")
    func browsingIsWhole() {
        #expect(PanelPresenter.present(PanelFixture.panel(Self.many)).rows.count == 20)
    }

    /// A row the cap left out must not be reachable by arrow key, or a paste arrives from nowhere.
    @Test("the arrows cannot reach a row the cap left out")
    func hiddenRowsAreUnreachable() {
        let panel = PanelFixture.panel(Self.many, query: "prod")
        let response = panel.applying(Array(repeating: PanelKey.down, count: 30) + [.return])

        guard case .insert(let clip) = response.outcome else {
            Issue.record("Return chose nothing")
            return
        }
        #expect(panel.results.rows.contains { $0.clip.id == clip.id })
    }
}

/// A row shows its first line, which is wrong when the match is on line forty.
@Suite("H5 · a match inside long content")
struct PanelMatchExcerptTests {
    /// A clip whose match is on its fourth line.
    static let long = PanelFixture.clip(
        """
        # Deployment notes
        first line that says nothing useful
        another line
        the connection string is postgres://user@prodhost:5432/main and it matters
        trailing line
        """, minutesAgo: 1)

    @Test("the row shows where the match was, not the first line")
    func showsTheMatch() {
        let page = PanelPresenter.present(PanelFixture.panel([Self.long], query: "prodhost"))
        let summary = page.rows[0].summary

        #expect(summary.contains("prodhost"))
        #expect(!summary.hasPrefix("# Deployment notes"))
        #expect(summary.contains("…"), "and says it is a window into something longer")
    }

    @Test("a match already on the first line is left alone")
    func firstLineIsUntouched() {
        let page = PanelPresenter.present(PanelFixture.panel([Self.long], query: "Deployment"))

        #expect(page.rows[0].summary == "# Deployment notes")
    }

    /// A row is one line high, so a newline in the excerpt would vanish or break alignment.
    @Test("the excerpt is flattened to one line")
    func excerptIsOneLine() {
        let page = PanelPresenter.present(PanelFixture.panel([Self.long], query: "prodhost"))

        #expect(!page.rows[0].summary.contains("\n"))
    }

    /// The excerpt would otherwise print exactly the searched-for part of a secret.
    @Test("a masked clip is never re-cut around the match")
    func maskedClipsStayMasked() {
        let secret = PanelFixture.clip(
            "line one\nline two\nsk-live-abcdef123456", kind: .secret, minutesAgo: 1)
        let page = PanelPresenter.present(PanelFixture.panel([secret], query: "sk-live"))

        #expect(page.rows[0].isMasked)
        #expect(!page.rows[0].summary.contains("sk-live"))
    }

    /// An alias or collection hit is already named on the row, so re-cutting would show nothing new.
    @Test("only a content match is re-cut")
    func onlyContentMatches() {
        let named = PanelFixture.clip("first line\nsecond line", minutesAgo: 1, alias: "notes")
        let page = PanelPresenter.present(PanelFixture.panel([named], query: "notes"))

        #expect(page.rows[0].summary == "first line")
    }
}

/// A fruitless search is often somebody discovering they never copied the thing they meant to.
@Suite("H3 · a search that found nothing")
struct PanelNoResultsTests {
    /// Nothing that matches "pgprod".
    static let clips = [PanelFixture.clip("something else entirely", minutesAgo: 1)]

    @Test("it names what was searched for")
    func namesTheQuery() {
        let page = PanelPresenter.present(PanelFixture.panel(Self.clips, query: "pgprod"))

        #expect(page.rows.isEmpty)
        #expect(page.emptyState?.message.contains("pgprod") == true)
    }

    @Test("and offers to keep it")
    func offersToKeepIt() {
        let page = PanelPresenter.present(PanelFixture.panel(Self.clips, query: "pgprod"))

        #expect(page.emptyAction?.intent == .keepQuery("pgprod"))
        #expect(page.emptyAction?.title.contains("pgprod") == true)
    }

    /// Keeping an empty field would create nothing, and the other empty states have nothing to keep.
    @Test(
        "the other empty states offer nothing, because there is nothing to keep",
        arguments: [
            PanelFixture.panel([]),
            PanelFixture.panel(clips, category: "Work"),
            PanelFixture.panel(clips, filter: .links),
        ])
    func nothingToOffer(panel: PanelSnapshot) {
        let page = PanelPresenter.present(panel)

        #expect(page.rows.isEmpty)
        #expect(page.emptyAction == nil)
    }

    /// Only the store can make a clip, so this is not a keystroke the panel can answer.
    @Test("keeping a query is an intent, not a key")
    func keepIsAnIntent() {
        #expect(PanelIntent.keepQuery("x").key == nil)
    }
}

/// Typing leaves the open collection behind silently, so the panel says the scope has widened.
@Suite("H7 · the scope of a search, said out loud")
struct PanelSearchScopeVisibilityTests {
    /// Two clips in different collections.
    static let clips = [
        PanelFixture.clip("one", minutesAgo: 1, category: "Work"),
        PanelFixture.clip("two", minutesAgo: 2, category: "Servers"),
    ]

    @Test("searching out of a collection says the scope has widened, and names it")
    func saysItWidened() {
        let page = PanelPresenter.present(
            PanelFixture.panel(Self.clips, query: "o", category: "Work"))

        #expect(page.scope?.contains("everywhere") == true)
        #expect(page.scope?.contains("Work") == true)
    }

    /// The active chip already answers the question, so browsing spends no line repeating it.
    @Test("browsing says nothing, because the chip already says it")
    func browsingIsSilent() {
        #expect(PanelPresenter.present(PanelFixture.panel(Self.clips, category: "Work")).scope == nil)
        #expect(PanelPresenter.present(PanelFixture.panel(Self.clips, query: "o")).scope == nil)
    }

    /// Naming the wrong key is worse than none: `esc` closes the panel, emptying the field goes back.
    @Test("it names the thing that actually returns you, not esc")
    func itNamesTheRightGesture() {
        let page = PanelPresenter.present(
            PanelFixture.panel(Self.clips, query: "o", category: "Work"))

        #expect(page.scope?.contains("clear the search") == true)
        #expect(page.scope?.contains("esc") == false)
    }
}
