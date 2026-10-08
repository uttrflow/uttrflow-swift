// Tests that reusing a shorter query's matches lists exactly what searching the whole history again would.
import Foundation
import UttrflowClipboard
import UttrflowTestSupport
import Testing

@testable import UttrflowUX

/// A list holding every shape of match the panel ranks, so a reused search has to agree about all of them.
@Suite("The quick panel: a search reused between keystroke")
struct PanelSearchMemoTests {
    static let clips = [
        PanelFixture.clip("the invoice for June, paid", minutesAgo: 1),
        PanelFixture.clip("nothing to do with it", minutesAgo: 2, alias: "invo"),
        PanelFixture.clip("a clip filed away", minutesAgo: 3, category: "Invoices"),
        PanelFixture.clip("INVOICE 4417", minutesAgo: 4, isPinned: true),
        PanelFixture.clip("invoice", minutesAgo: 5),
        PanelFixture.clip("l'entrée du café — invoiced", minutesAgo: 6),
        PanelFixture.clip("\u{2018}invoice\u{2019} and an  em\u{2014}dash", minutesAgo: 7),
        PanelFixture.clip("a receipt, not an invoice", minutesAgo: 8, alias: "inv-prod"),
        PanelFixture.clip("https://example.com/invoice", kind: .link, minutesAgo: 9),
        PanelFixture.clip("let invoice = 1", kind: .code, minutesAgo: 10),
    ]

    /// The rows a panel with no memory of an earlier query lists, which is what the fix has to match.
    static func fromScratch(_ query: String, filter: PanelFilter = .all) -> PanelResults {
        PanelFixture.panel(clips, query: query, filter: filter).results
    }

    /// Compares rows, why each is here, the order, the cap and the selection.
    static func same(_ lhs: PanelResults, _ rhs: PanelResults) -> Bool {
        lhs.rows == rhs.rows && lhs.omitted == rhs.omitted && lhs.selectedIndex == rhs.selectedIndex
    }

    @Test(
        "typing a query letter by letter lists what searching for it cold lists",
        arguments: [
            "invoice", "inv-prod", "/invo", "Invoices", "café", "zqx",
        ])
    func typing(query: String) {
        var panel = PanelFixture.panel(Self.clips)

        for length in 1...query.count {
            let typed = String(query.prefix(length))
            panel = panel.applying(.search(typed)).state

            #expect(
                Self.same(panel.results, Self.fromScratch(typed)),
                "after typing \(typed)")
        }
    }

    @Test("fold-sensitive Unicode searches match a fresh scan as they grow")
    func foldSensitiveQueries() {
        let combiningClips = [
            PanelFixture.clip("cafe\u{0301}", minutesAgo: 1),
            PanelFixture.clip("café", minutesAgo: 2),
            PanelFixture.clip("apple", minutesAgo: 3),
            PanelFixture.clip("thé", minutesAgo: 4),
            PanelFixture.clip("résumé", minutesAgo: 5),
            PanelFixture.clip("crème", minutesAgo: 6),
        ]
        let cases: [([Clip], [String])] = [
            ([PanelFixture.clip("Fuß", minutesAgo: 1)], ["f", "fu", "fus", "fuss"]),
            ([PanelFixture.clip("Maße", minutesAgo: 1)], ["m", "ma", "mas", "mass"]),
            ([PanelFixture.clip("Straße", minutesAgo: 1)], ["s", "st", "str", "stras", "strass", "strasse"]),
            ([PanelFixture.clip("\u{FB01}le", minutesAgo: 1)], ["f", "fi", "fil"]),
            ([PanelFixture.clip("\u{FB00}", minutesAgo: 1)], ["f", "ff"]),
            ([PanelFixture.clip("\u{0149}", minutesAgo: 1)], ["ʼ", "ʼn"]),
            (combiningClips, ["e", "e\u{0301}", "\u{0301}"]),
            ([PanelFixture.clip("ordinary text", minutesAgo: 1)], ["o", "or", "ord", "ordinary"]),
        ]

        for (clips, queries) in cases {
            var panel = PanelFixture.panel(clips)
            for typed in queries {
                panel = panel.applying(.search(typed)).state
                let fresh = PanelFixture.panel(clips, query: typed).results

                #expect(Self.same(panel.results, fresh), "after typing \(typed)")
            }
        }
    }

    @Test("seeded random incremental queries match a fresh search")
    func randomizedIncrementalQueries() {
        let alphabet: [Unicode.Scalar] = ["f", "u", "s", "ß", "ﬁ", "e", "\u{0301}", "é", "x"]
        let foldingClips = [
            PanelFixture.clip("Fuß", minutesAgo: 1),
            PanelFixture.clip("\u{FB01}le", minutesAgo: 2),
            PanelFixture.clip("cafe\u{0301}", minutesAgo: 3),
        ]
        var random = Seeded(seed: 438_300)

        for clips in [Self.clips, foldingClips] {
            var query = ""
            var panel = PanelFixture.panel(clips)
            for _ in 0..<100 {
                query.unicodeScalars.append(alphabet[Int(random.next() % UInt64(alphabet.count))])
                panel = panel.applying(.search(query)).state
                let fresh = PanelFixture.panel(clips, query: query).results

                #expect(Self.same(panel.results, fresh), "seed=438300 after \(query)")
            }
        }
    }

    @Test("deleting a character searches again rather than keeping the narrower list")
    func backspace() {
        var panel = PanelFixture.panel(Self.clips)
        for typed in ["i", "in", "inv", "invo", "invoi", "invo", "inv", "in", "i", ""] {
            panel = panel.applying(.search(typed)).state

            #expect(Self.same(panel.results, Self.fromScratch(typed)), "after \(typed)")
        }
    }

    @Test("pasting an unrelated query over the old one searches again")
    func replacedQuery() {
        var panel = PanelFixture.panel(Self.clips)
        for typed in ["invoice", "receipt", "Invoices", "let", "\u{0915}\u{0930}", "invoice"] {
            panel = panel.applying(.search(typed)).state

            #expect(Self.same(panel.results, Self.fromScratch(typed)), "after \(typed)")
        }
    }

    @Test("a clip found only by its name is searched by its text once the name stops matching")
    func aliasThenText() {
        let panel = PanelFixture.panel(Self.clips)
            .applying(.search("inv")).state
            .applying(.search("invo")).state
            .applying(.search("invoice")).state

        #expect(Self.same(panel.results, Self.fromScratch("invoice")))
        #expect(
            panel.results.rows.contains { $0.clip.alias == "inv-prod" && $0.match == .content },
            "the clip named inv-prod is still listed, now for its text")
    }

    @Test("changing the kind tab mid-search searches again")
    func filterChange() {
        var panel = PanelFixture.panel(Self.clips).applying(.search("invoice")).state
        _ = panel.results
        for filter in [PanelFilter.links, .code, .all, .text] {
            panel = panel.applying(.filter(filter)).state

            #expect(Self.same(panel.results, Self.fromScratch("invoice", filter: filter)))
        }
    }

    @Test("a new clip list searches again rather than answering from the old one")
    func installedClips() {
        var panel = PanelFixture.panel(Self.clips).applying(.search("invoice")).state
        _ = panel.results
        let arrived = [PanelFixture.clip("a late invoice", minutesAgo: 0)] + Self.clips
        panel.install(arrived, missingImages: [], formattableLanguages: [], now: PanelFixture.now)

        #expect(
            Self.same(
                panel.results,
                PanelFixture.panel(arrived, query: "invoice").results))
        #expect(panel.results.rows.contains { $0.clip.text == "a late invoice" })
    }

    @Test("an arrow key moves the selection without changing the list")
    func arrowKeeps() {
        let searched = PanelFixture.panel(Self.clips).applying(.search("invoice")).state
        let moved = searched.applying(.down).state

        #expect(moved.results.rows == searched.results.rows)
        #expect(moved.results.selectedIndex == 1)
    }

    @Test("only a query that grew reuses the search")
    func reuseRule() {
        let base = PanelFixture.panel(Self.clips)
        func view(
            _ query: String, filter: PanelFilter = .all, clips: [Clip]? = nil
        )
            -> PanelSearchMemo.View
        {
            var panel = clips.map { PanelFixture.panel($0) } ?? base
            panel.query = query
            panel.filter = filter
            return PanelSearchMemo.View(panel)
        }

        #expect(view("inv").narrows(to: view("invo")))
        #expect(view("/inv").narrows(to: view("/invo")), "the slash is part of what was typed")
        #expect(view("inv").narrows(to: view("an inv")), "a query pasted around the old one")
        #expect(!view("invo").narrows(to: view("inv")), "a deleted character")
        #expect(!view("inv").narrows(to: view("receipt")), "a query pasted over the old one")
        #expect(!view("").narrows(to: view("i")), "nothing was searched before")
        #expect(!view("inv").narrows(to: view("")), "the field was emptied")
        #expect(!view("inv").narrows(to: view("invo", filter: .links)), "another kind tab")
        #expect(
            !view("inv").narrows(to: view("invo", clips: Array(Self.clips.dropFirst()))),
            "a clip arrived or was deleted")
    }

    @Test("a search ignores browsing scope and collection without rescanning")
    func scopeAndCategoryDuringSearch() {
        let history = PanelFixture.panel(Self.clips, query: "invoice")
        var pinnedCollection = PanelFixture.panel(Self.clips, query: "invoice")
        pinnedCollection.scope = .pinned
        pinnedCollection.category = "Invoices"
        let historyView = PanelSearchMemo.View(history)
        let pinnedCollectionView = PanelSearchMemo.View(pinnedCollection)

        #expect(historyView == pinnedCollectionView)

        let memo = PanelSearchMemo()
        var scans = 0
        let first = memo.rows(
            for: historyView,
            scanning: { ruledIn in
                scans += 1
                return history.matches(ruledIn: ruledIn)
            },
            ranking: history.ranked)
        let second = memo.rows(
            for: pinnedCollectionView,
            scanning: { ruledIn in
                scans += 1
                return pinnedCollection.matches(ruledIn: ruledIn)
            },
            ranking: pinnedCollection.ranked)

        #expect(scans == 1)
        #expect(first.0 == second.0)
        #expect(first.1 == second.1)

        let emptySearch = PanelFixture.panel(Self.clips)
        var otherBrowsingScope = emptySearch
        otherBrowsingScope.scope = .pinned
        #expect(PanelSearchMemo.View(emptySearch) != PanelSearchMemo.View(otherBrowsingScope))
        var otherBrowsingCategory = emptySearch
        otherBrowsingCategory.category = "Invoices"
        #expect(
            PanelSearchMemo.View(emptySearch) != PanelSearchMemo.View(otherBrowsingCategory))

        var grownQueryInAnotherCollection = PanelFixture.panel(Self.clips, query: "invo")
        grownQueryInAnotherCollection.scope = .collections
        grownQueryInAnotherCollection.category = "Invoices"
        var shorterQuery = PanelFixture.panel(Self.clips, query: "inv")
        shorterQuery.scope = .history
        #expect(
            PanelSearchMemo.View(shorterQuery).narrows(
                to: PanelSearchMemo.View(grownQueryInAnotherCollection)))
    }

    /// Lists `queries` through one memo and counts the clips whose own text each one searched.
    static func textSearched(_ queries: [String]) -> [Int] {
        let memo = PanelSearchMemo()
        var panel = PanelFixture.panel(clips)
        return queries.map { query in
            panel.query = query
            var searched = 0
            _ = memo.rows(
                for: PanelSearchMemo.View(panel),
                scanning: { ruledIn in
                    searched =
                        ruledIn.map { ids in panel.clips.filter { ids.contains($0.id) }.count }
                        ?? panel.clips.count
                    return panel.matches(ruledIn: ruledIn)
                },
                ranking: panel.ranked)
            return searched
        }
    }

    @Test("deleting back to a query searched earlier searches no clip's text again")
    func backspaceReuses() {
        let searched = Self.textSearched(["i", "in", "inv", "in", "i"])

        #expect(Array(searched.suffix(2)) == [0, 0])
    }

    @Test("a query that returns after another one searches no clip's text again")
    func returningQuery() {
        #expect(Self.textSearched(["invoice", "receipt", "invoice"]).last == 0)
    }

    @Test("a query that grows again after a Backspace is searched in the narrowest earlier list")
    func regrowth() {
        let searched = Self.textSearched(["i", "invoi", "invo", "invoic"])

        #expect(searched[2] <= searched[0], "invo is searched within what i found")
        #expect(searched[3] <= searched[1], "invoic is searched within what invoi found")
    }

    @Test("a new clip list forgets every earlier list")
    func clipsForgetAll() {
        let memo = PanelSearchMemo()
        let before = PanelFixture.panel(Self.clips, query: "inv")
        let after = PanelFixture.panel(Array(Self.clips.dropFirst()), query: "in")
        var ruled: [Set<Clip.ID>?] = []
        for panel in [before, after] {
            _ = memo.rows(
                for: PanelSearchMemo.View(panel),
                scanning: { ruledIn in
                    ruled.append(ruledIn)
                    return panel.matches(ruledIn: ruledIn)
                },
                ranking: panel.ranked)
        }

        #expect(ruled.count == 2 && ruled[1] == nil)
    }

    /// The store does not drop a repeated id from an index file, so a list holding a clip twice must still open the panel.
    @Test("a clip listed twice selects its first row")
    func repeatedClip() {
        let clip = Self.clips[0]
        let panel = PanelFixture.panel([clip, Self.clips[1], clip])
        let memo = PanelSearchMemo()
        let view = PanelSearchMemo.View(panel)

        let (rows, _, _) = memo.rows(for: view, scanning: panel.matches(ruledIn:), ranking: panel.ranked)

        #expect(rows.filter { $0.id == clip.id }.count == 2)
        #expect(memo.index(of: clip.id, for: view) == rows.firstIndex { $0.id == clip.id })
    }

    @Test("walking a query back and forth lists what searching for it cold lists")
    func backAndForth() {
        var panel = PanelFixture.panel(Self.clips)
        for typed in ["inv", "invoice", "inv", "invo", "i", "invoices", "in", "", "invoice"] {
            panel = panel.applying(.search(typed)).state

            #expect(Self.same(panel.results, Self.fromScratch(typed)), "after \(typed)")
        }
    }
}
