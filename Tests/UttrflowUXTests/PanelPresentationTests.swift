import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

extension PanelFixture {
    static func page(
        _ clips: [Clip] = clips,
        query: String = "",
        filter: PanelFilter = .all,
        category: String? = nil,
        revealed: Set<Clip.ID> = [],
        scope: PanelScope = .history
    ) -> PanelPresentation {
        var snapshot = panel(
            clips, query: query, filter: filter, category: category, revealed: revealed)
        snapshot.scope = scope
        return PanelPresenter.present(snapshot)
    }
}

@Suite("The quick panel: what a row shows")
struct PanelRowTests {
    @Test("a row is the clip's one line, when it was copied, and what it is")
    func row() {
        let clip = PanelFixture.clip(
            "postgres://user@prod\nsecond line", minutesAgo: 2, alias: "/pgprod",
            category: " Prod ", isPinned: true)

        // Under Pinned, because that is where a pinned clip now is: History stopped
        // showing them, and a fixture that pinned a clip and then read row zero of
        // History was reading an empty list — which is a crash, not a failed
        // expectation, and takes the whole run with it.
        let row = PanelFixture.page([clip], scope: .pinned).rows[0]

        #expect(row.id == clip.id)
        #expect(row.summary == "postgres://user@prod", "one line, whatever was copied")
        #expect(row.when == "2 minutes ago")
        #expect(row.kind == .text)
        #expect(row.alias == "/pgprod")
        #expect(row.category == "Prod")
        #expect(row.isPinned)
        #expect(row.isSelected, "the only row there is")
        #expect(row.matched == nil)
        #expect(!row.isMasked)
    }

    @Test("the selected row is the one Return would insert, and only it")
    func selection() {
        let page = PanelPresenter.present(PanelFixture.panel().applying([.down]).state)

        #expect(page.rows.map(\.isSelected) == [false, true, false])
        #expect(page.selectedRow?.id == PanelFixture.clips[1].id)
    }

    @Test("an empty list has no selected row")
    func nothingSelected() {
        #expect(PanelFixture.page([]).selectedRow == nil)
    }

    @Test("a row says which part of the clip the search found")
    func matched() {
        let clips = [
            PanelFixture.clip("postgres://prod", minutesAgo: 1, alias: "/pgprod"),
            PanelFixture.clip("pgprod is the old name", minutesAgo: 2),
        ]

        #expect(PanelFixture.page(clips, query: "pgprod").rows.map(\.matched) == [.alias, .content])
    }

    @Test("every kind of clip has its own icon", arguments: ClipKind.allCases)
    func icons(kind: ClipKind) {
        let row = PanelFixture.page([PanelFixture.clip("something", kind: kind)]).rows[0]

        #expect(!row.symbolName.isEmpty)
        #expect(row.kind == kind)
        #expect(row.symbolName == PanelPresenter.symbolName(for: kind))
    }

    @Test("icons are not shared between kinds")
    func iconsAreDistinct() {
        let icons = ClipKind.allCases.map(PanelPresenter.symbolName(for:))

        #expect(Set(icons).count == ClipKind.allCases.count)
    }

    /// Where the characters matter one by one rather than as words.
    @Test("code, colours, secrets and paths are set in a monospaced face")
    func monospaced() {
        for kind in ClipKind.allCases {
            let row = PanelFixture.page([PanelFixture.clip("x", kind: kind)]).rows[0]
            #expect(row.isMonospaced == [.code, .colour, .secret, .filePath].contains(kind), "\(kind)")
        }
    }

    /// The order is the argument. Insert first because it is what the row is for; the
    /// three that change a clip after the two that only read it; Delete last, because it
    /// is the one that repeating does not undo.
    @Test("a row offers everything that can be done to a clip, in that order")
    func actions() {
        let clip = PanelFixture.clip()
        let row = PanelFixture.page([clip]).rows[0]

        #expect(
            row.actions.map(\.intent) == [
                .insert(clip.id), .copy(clip.id), .pin(clip.id), .alias(clip.id),
                .move(clip.id), .makeNote(clip.id), .delete(clip.id),
            ])
        #expect(
            row.actions.map(\.id)
                == ["Insert", "Copy", "Pin", "Name", "Move", "Make a note", "Delete"])
        #expect(row.actions.allSatisfy { !$0.symbolName.isEmpty })
    }

    @Test("the pin reads Unpin on a pinned clip, and naming reads Rename on a named one")
    func actionsReadTheirEffect() {
        let pinned = PanelFixture.page(
            [PanelFixture.clip("pinned", isPinned: true)], scope: .pinned
        ).rows[0]
        let named = PanelFixture.page([PanelFixture.clip("named", alias: "thing")]).rows[0]

        #expect(pinned.actions.map(\.title).contains("Unpin"))
        #expect(!pinned.actions.map(\.title).contains("Pin"))
        // "Name" over a clip that has one invites the user to expect a second alias.
        #expect(named.actions.map(\.title).contains("Rename"))
        #expect(!named.actions.map(\.title).contains("Name"))
    }

    /// The row's own Insert and the Return key are one path, not two implementations of
    /// the same sentence that can drift apart.
    @Test("a row's Insert is the same keystroke as clicking it")
    func insertIsAKey() {
        let clip = PanelFixture.clip()
        let insert = PanelFixture.page([clip]).rows[0].actions[0]

        #expect(insert.intent.key == .choose(clip.id))
        #expect(PanelIntent.reveal(clip.id).key == .reveal(clip.id))
        #expect(PanelIntent.copy(clip.id).key == nil, "only the store can do that one")
        #expect(PanelIntent.pin(clip.id).key == nil)
        #expect(PanelIntent.unpin(clip.id).key == nil)
    }
}

@Suite("The quick panel: a secret is masked until it is asked for")
struct PanelMaskTests {
    static let secret = PanelFixture.clip("sk-live-abcdef123456", kind: .secret)

    @Test("a secret is masked, and the row says so")
    func masked() {
        let row = PanelFixture.page([Self.secret]).rows[0]

        #expect(row.isMasked)
        #expect(!row.summary.contains("sk-live"))
        #expect(row.summary.allSatisfy { $0 == "•" })
    }

    /// The length of a token is worth something to whoever is looking over the user's
    /// shoulder, so the mask is the same width whatever it covers.
    @Test("the mask does not leak how long the secret is")
    func maskWidth() {
        let short = PanelFixture.page([PanelFixture.clip("abc", kind: .secret)]).rows[0]

        #expect(short.summary == PanelFixture.page([Self.secret]).rows[0].summary)
    }

    @Test("revealing shows that one secret and nothing else")
    func revealed() {
        let other = PanelFixture.clip("sk-live-999", kind: .secret, minutesAgo: 1)
        let page = PanelFixture.page([Self.secret, other], revealed: [Self.secret.id])

        #expect(page.rows[0].summary == "sk-live-abcdef123456")
        #expect(!page.rows[0].isMasked)
        #expect(page.rows[1].isMasked)
    }

    /// C6 — the tooltip is the whole line, and a masked row has none.
    ///
    /// Removing the rule does not spill the secret: the summary is already bullets, so a
    /// tooltip would be bullets. It would still be wrong — a panel appearing under the
    /// cursor reads as the mask being lifted, and there is nothing there to give back.
    /// The rule used to live in the view as a condition on `.help`, which no test could
    /// reach, which is the reason it is here now.
    @Test("a masked row has no tooltip at all")
    func maskedRowsHaveNoTooltip() {
        let row = PanelFixture.page([Self.secret]).rows[0]

        #expect(row.tooltip == nil)
    }

    /// And the row is not simply tooltip-less for ever: revealing the same clip gives one,
    /// and it is the real line rather than a row of bullets.
    @Test("revealing it gives one, and it is the real line")
    func revealedRowsDo() {
        let page = PanelFixture.page([Self.secret], revealed: [Self.secret.id])

        #expect(page.rows[0].tooltip == "sk-live-abcdef123456")
    }

    @Test("a masked row offers to reveal itself, and a revealed one does not")
    func revealAction() {
        let masked = PanelFixture.page([Self.secret]).rows[0]
        let shown = PanelFixture.page([Self.secret], revealed: [Self.secret.id]).rows[0]

        #expect(masked.actions.map(\.title).contains("Reveal"))
        #expect(!shown.actions.map(\.title).contains("Reveal"))
        // Reveal is inserted after Insert, before everything that only reads the clip:
        // it is the thing that has to happen before the user can judge the rest.
        #expect(masked.actions.map(\.title).firstIndex(of: "Reveal") == 1)
        #expect(shown.actions.map(\.title) == masked.actions.map(\.title).filter { $0 != "Reveal" })
    }
}

@Suite("The quick panel: the tabs and the collections")
struct PanelChipTests {
    @Test("every tab is offered, and one of them is on")
    func filters() {
        let page = PanelFixture.page(filter: .links)

        #expect(page.filters.map(\.title) == ["All", "Text", "Links", "Code", "Images"])
        #expect(page.filters.map(\.id) == PanelFilter.allCases.map(\.rawValue))
        #expect(page.filters.filter(\.isActive).map(\.filter) == [.links])
    }

    /// A lone "All" chip is a row of the panel spent telling the user something they can
    /// already see.
    @Test("nothing filed anywhere means no collection chips at all")
    func noCategories() {
        #expect(PanelFixture.page().categories.isEmpty)
    }

    @Test("the collections are numbered from ⌘2, and ⌘1 is the way back")
    func categories() {
        let clips = [
            PanelFixture.clip("one", minutesAgo: 1, category: "Prod"),
            PanelFixture.clip("two", minutesAgo: 2, category: "Personal"),
        ]

        let page = PanelFixture.page(clips, category: "Personal")

        #expect(page.categories.map(\.title) == ["Prod", "Personal"])
        #expect(page.categories.map(\.shortcut) == [2, 3])
        #expect(page.categories.map(\.isActive) == [false, true])
        #expect(page.categories.map(\.category) == ["Prod", "Personal"])
        #expect(page.categories.map(\.id) == ["Prod", "Personal"])
    }

    /// There is never an "All" chip beside the collections.
    ///
    /// They share a row with the kind filters, which already begins with an "All"
    /// meaning every kind. A second one meaning every collection reads as a bug — and
    /// drawing it only while a collection was chosen just moved the confusion to the
    /// moment somebody was looking at it, which is exactly when it was reported.
    @Test("there is no All chip, chosen or not")
    func neverAnAllChip() {
        let clips = [PanelFixture.clip("one", category: "Prod")]

        let idle = PanelFixture.page(clips)
        let chosen = PanelFixture.page(clips, category: "Prod")

        #expect(idle.categories.map(\.title) == ["Prod"])
        #expect(chosen.categories.map(\.title) == ["Prod"])
        #expect(!chosen.categories.contains { $0.category == nil })
    }

    /// So the way out of a collection has to be the collection itself. `chosen` is what
    /// pressing a chip sends, and for the one already showing it is 1 — everything.
    @Test("pressing the collection you are in takes you back to everything")
    func theActiveChipIsTheWayOut() {
        let clips = [PanelFixture.clip("one", category: "Prod")]

        let idle = try! #require(PanelFixture.page(clips).categories.first)
        let chosen = try! #require(PanelFixture.page(clips, category: "Prod").categories.first)

        #expect(idle.chosen == 2, "pressing it shows that collection")
        #expect(chosen.chosen == 1, "pressing it again shows everything")
    }

    /// There is no ⌘10, and printing a shortcut that does nothing is worse than printing
    /// none at all. What a chip *prints* stops at the ninth; what pressing it *means*
    /// does not — see the test below, which is the half that was broken.
    @Test("collections past the ninth are drawn without a number")
    func pastTheNinth() {
        let clips = (1...12).map { PanelFixture.clip("c\($0)", minutesAgo: $0, category: "C\($0)") }

        let shortcuts = PanelFixture.page(clips).categories.map(\.shortcut)

        #expect(shortcuts == [2, 3, 4, 5, 6, 7, 8, 9, nil, nil, nil, nil])
    }

    /// Printing no number is not the same as doing nothing.
    ///
    /// The chip's position used to *be* its shortcut, so every collection past the ninth
    /// sent 0, which the snapshot rejects. They were drawn like the others, said nothing
    /// about being different, and did nothing at all when clicked — while a comment in
    /// the view claimed they were "still clickable".
    @Test("but they can still be pressed")
    func pastTheNinthStillWorks() {
        let clips = (1...12).map { PanelFixture.clip("c\($0)", minutesAgo: $0, category: "C\($0)") }
        let chips = PanelFixture.page(clips).categories

        #expect(chips.allSatisfy { $0.chosen >= 1 })
        #expect(chips.map(\.chosen) == Array(2...13))
    }
}

@Suite("The quick panel: the words around the list")
struct PanelChromeTests {
    @Test("the field says what it is for, and what makes the panel fast")
    func placeholder() {
        let page = PanelFixture.page(query: "prod")

        #expect(page.searchPlaceholder == "Search, or type an alias")
        #expect(page.query == "prod")
    }

    @Test("the panel teaches the three keystrokes under the list")
    func hint() {
        #expect(PanelFixture.page().hint == "↑↓ to choose · ⏎ to paste · esc to close")
    }

    /// Promising ↑↓ and ⏎ over an empty list is a small lie, and the panel is most
    /// people's only lesson in how it works.
    @Test("an empty list only promises the key that works")
    func emptyHint() {
        #expect(PanelFixture.page([]).hint == "esc to close")
    }

    @Test("nothing copied yet says so")
    func nothingCopied() {
        let page = PanelFixture.page([])

        #expect(page.emptyState?.title == "Nothing copied yet")
        #expect(page.rows.isEmpty)
    }

    @Test("a search that matches nothing repeats what was searched for")
    func noMatches() {
        let page = PanelFixture.page(query: "zzz")

        #expect(page.emptyState?.title == "No matches")
        // "you have copied" was true while the clipboard was one list. A search now
        // spans what Uttrflow made as well.
        #expect(page.emptyState?.message == "Nothing on your clipboard mentions “zzz”.")
    }

    @Test("an empty collection names the collection")
    func emptyCategory() {
        let clips = [PanelFixture.clip("one", category: "Prod")]
        let page = PanelFixture.page(clips, filter: .images, category: "Prod")

        #expect(page.emptyState?.title == "No Images in Prod")
    }

    /// The chip row can no longer reach this state — one chip at a time, so a kind and a
    /// collection cannot both be on. The presenter stays total over it anyway: a
    /// presentation that answers only the states today's UI can produce is one that
    /// breaks silently the next time the UI changes, and this is the exact combination
    /// that broke silently last time.
    ///
    /// This test used to set a collection *and* a kind filter and assert that only the
    /// collection was named — the reported bug, written down as the rule. "Nothing you
    /// have copied is filed here" was said over a collection with clips in it, because
    /// the kind was doing the hiding and went unmentioned. An empty state that names one
    /// of two reasons is worse than a vague one: it is specific and wrong.
    @Test("but when a kind is narrowing too, it says so rather than blaming the collection")
    func emptyCategoryWithAKind() {
        let clips = [PanelFixture.clip("plain words", category: "db")]

        let page = PanelFixture.page(clips, filter: .code, category: "db")

        #expect(page.emptyState?.title == "No Code in db")
        #expect(page.emptyState?.message == "Nothing filed in db is code.")
        #expect(page.emptyState?.message.contains("is filed here") == false)
    }

    /// The collection alone still reads as it did, because then it is the whole reason.
    @Test("a collection with nothing in it, and no other narrowing, still says so plainly")
    func emptyCategoryAlone() {
        let clips = [PanelFixture.clip("one", category: "Prod")]

        let page = PanelFixture.page(clips, category: "Empty")

        #expect(page.emptyState?.title == "Nothing in Empty")
        #expect(page.emptyState?.message == "Nothing you have copied is filed here.")
    }

    /// The title gained "copied" when History stopped meaning everything: it is now the
    /// tab that holds what came off a ⌘C, beside the one that holds what Uttrflow made,
    /// so an empty one has a place to name like every other tab does.
    @Test("an empty tab names what it was looking for")
    func emptyTab() {
        let page = PanelFixture.page(filter: .links)

        #expect(page.emptyState?.title == "No Links copied")
        #expect(page.emptyState?.message == "Nothing you have copied is a link.")
    }

    @Test("a list with something in it has no empty state")
    func notEmpty() {
        #expect(PanelFixture.page().emptyState == nil)
    }

    /// Read only when a tab is empty, and every tab needs one so that the table cannot be
    /// left incomplete by whoever adds the next tab.
    @Test("every tab can say what it was looking for", arguments: PanelFilter.allCases)
    func nouns(filter: PanelFilter) {
        #expect(!filter.noun.isEmpty)
        #expect(!filter.title.isEmpty)
    }
}
