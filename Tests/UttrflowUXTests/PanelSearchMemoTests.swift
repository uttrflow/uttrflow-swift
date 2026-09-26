// Tests that reusing a shorter query's matches lists exactly what searching the whole history again would.
import Foundation
import UttrflowClipboard
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
        PanelFixture.clip("\u{FF49}\u{FF4E}\u{FF56}oice in full width", minutesAgo: 9),
        PanelFixture.clip("\u{0915}\u{093C}\u{0930}\u{094D}\u{0937} and \u{0915}\u{0930}", minutesAgo: 10),
        PanelFixture.clip("KAR with no nukta", minutesAgo: 11, alias: "\u{0915}\u{0930}"),
        PanelFixture.clip("https://example.com/invoice", kind: .link, minutesAgo: 12),
        PanelFixture.clip("let invoice = 1", kind: .code, minutesAgo: 13),
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
        arguments: ["invoice", "inv-prod", "/invo", "Invoices", "café", "\u{0915}\u{0930}", "zqx"])
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
        panel.install(arrived, missingImages: [], formattableLanguages: [])

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
        func view(
            _ query: String, filter: PanelFilter = .all, clips: [Clip] = Self.clips
        )
            -> PanelSearchMemo.View
        {
            PanelSearchMemo.View(PanelFixture.panel(clips, query: query, filter: filter))
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

    /// Lists `queries` through one memo and counts the clips whose own text each one searched.
    static func textSearched(_ queries: [String]) -> [Int] {
        let memo = PanelSearchMemo()
        return queries.map { query in
            let panel = PanelFixture.panel(clips, query: query)
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

    @Test("walking a query back and forth lists what searching for it cold lists")
    func backAndForth() {
        var panel = PanelFixture.panel(Self.clips)
        for typed in ["inv", "invoice", "inv", "invo", "i", "invoices", "in", "", "invoice"] {
            panel = panel.applying(.search(typed)).state

            #expect(Self.same(panel.results, Self.fromScratch(typed)), "after \(typed)")
        }
    }
}
