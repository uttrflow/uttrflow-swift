// Tests for what the panel draws: rows, masking, the chips, and the words around the list.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

extension PanelFixture {
    /// The panel's presentation over these inputs.
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

        // Under Pinned, because that is where a pinned clip is; row zero of History would be an empty list.
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

    /// Insert first because it is what the row is for; the writers after the readers; Delete last.
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

    /// The row's own Insert and the Return key are one path, not two implementations that can drift.
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
    /// A masked clip.
    static let secret = PanelFixture.clip("sk-live-abcdef123456", kind: .secret)

    @Test("a secret is masked, and the row says so")
    func masked() {
        let row = PanelFixture.page([Self.secret]).rows[0]

        #expect(row.isMasked)
        #expect(!row.summary.contains("sk-live"))
        #expect(row.summary.allSatisfy { $0 == "•" })
    }

    /// The length of a token is worth something over the user's shoulder, so the mask has one width.
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

    /// The tooltip is the whole line, and a masked row has none, since a tooltip reads as the mask lifting.
    @Test("a masked row has no tooltip at all")
    func maskedRowsHaveNoTooltip() {
        let row = PanelFixture.page([Self.secret]).rows[0]

        #expect(row.tooltip == nil)
    }

    /// Revealing the same clip gives a tooltip, and it is the real line rather than bullets.
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
        // Reveal comes after Insert and before everything that only reads the clip.
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

    /// A lone "All" chip is a row of the panel spent telling the user something they can already see.
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

    /// There is never an "All" chip beside the collections; the kind filters' All already begins the row.
    @Test("there is no All chip, chosen or not")
    func neverAnAllChip() {
        let clips = [PanelFixture.clip("one", category: "Prod")]

        let idle = PanelFixture.page(clips)
        let chosen = PanelFixture.page(clips, category: "Prod")

        #expect(idle.categories.map(\.title) == ["Prod"])
        #expect(chosen.categories.map(\.title) == ["Prod"])
        #expect(!chosen.categories.contains { $0.category == nil })
    }

    /// The way out of a collection is the collection itself: its `chosen` is 1, everything, while showing.
    @Test("pressing the collection you are in takes you back to everything")
    func theActiveChipIsTheWayOut() {
        let clips = [PanelFixture.clip("one", category: "Prod")]

        let idle = try! #require(PanelFixture.page(clips).categories.first)
        let chosen = try! #require(PanelFixture.page(clips, category: "Prod").categories.first)

        #expect(idle.chosen == 2, "pressing it shows that collection")
        #expect(chosen.chosen == 1, "pressing it again shows everything")
    }

    /// There is no ⌘10; what a chip prints stops at the ninth, what pressing it means does not.
    @Test("collections past the ninth are drawn without a number")
    func pastTheNinth() {
        let clips = (1...12).map { PanelFixture.clip("c\($0)", minutesAgo: $0, category: "C\($0)") }

        let shortcuts = PanelFixture.page(clips).categories.map(\.shortcut)

        #expect(shortcuts == [2, 3, 4, 5, 6, 7, 8, 9, nil, nil, nil, nil])
    }

    /// Printing no number is not the same as doing nothing: every chip past the ninth still sends a jump.
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

    /// Promising ↑↓ and ⏎ over an empty list is a small lie, and the panel is most people's only lesson.
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
        // A search spans what Uttrflow made as well, so the sentence says "your clipboard".
        #expect(page.emptyState?.message == "Nothing on your clipboard mentions “zzz”.")
    }

    @Test("an empty collection names the collection")
    func emptyCategory() {
        let clips = [PanelFixture.clip("one", category: "Prod")]
        let page = PanelFixture.page(clips, filter: .images, category: "Prod")

        #expect(page.emptyState?.title == "No Images in Prod")
    }

    /// The presenter stays total over a kind and a collection together, though the chips cannot reach it.
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

    /// History is the tab holding what came off a ⌘C, so an empty one has a place to name like every tab.
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

    /// Read only when a tab is empty, and every tab needs one so the table cannot be left incomplete.
    @Test("every tab can say what it was looking for", arguments: PanelFilter.allCases)
    func nouns(filter: PanelFilter) {
        #expect(!filter.noun.isEmpty)
        #expect(!filter.title.isEmpty)
    }
}
