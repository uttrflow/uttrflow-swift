// Tests for the sidebar: row order, groups, selection, the corrections badge, the version and the account card.
import Foundation
import UttrflowSettings
import Testing

@testable import UttrflowUX

extension HistoryFixture {
    /// The sidebar over these inputs.
    static func sidebar(
        selection: SidebarDestination = .page(.corrections),
        entries: [HistoryEntry] = [],
        correctionsToday: Int = 0,
        shortcutKeys: [String] = ["⌥", "Space"],
        settings: Settings = .default
    ) -> SidebarPresentation {
        SidebarPresenter.sidebar(
            for: SidebarSnapshot(
                selection: selection, entries: entries, correctionsToday: correctionsToday,
                shortcutKeys: shortcutKeys, settings: settings, now: now),
            calendar: calendar, locale: locale)
    }
}

@Suite("The sidebar's destinations")
struct SidebarOrderTests {
    /// The design's order, pinned: Settings sits last though it is not a page.
    @Test("the rows are in the designed order")
    func order() {
        #expect(
            HistoryFixture.sidebar().items.map(\.title) == [
                "Home", "History", "Insights", "Dictionary", "Snippets", "Settings",
            ])
    }

    /// Those pages stay in the window, reached from elsewhere, until their content moves into Settings.
    @Test("the sidebar leaves out the pages the design moved off it")
    func pagesOffTheSidebar() {
        let reached = HistoryFixture.sidebar().items.compactMap { item -> MainTab? in
            guard case .page(let page) = item.destination else { return nil }
            return page
        }
        #expect(
            Set(MainTab.allCases).subtracting(reached)
                == [.corrections, .account])
    }

    @Test("the rows fall into three groups, with a heading over the user's words")
    func sections() {
        let sidebar = HistoryFixture.sidebar()
        #expect(sidebar.items(in: .main).map(\.title) == ["Home", "History", "Insights"])
        #expect(sidebar.items(in: .yourWords).map(\.title) == ["Dictionary", "Snippets"])
        #expect(sidebar.items(in: .footer).map(\.title) == ["Settings"])
        #expect(SidebarSection.yourWords.title == "Your words")
        #expect(SidebarSection.main.title == nil)
        #expect(SidebarSection.footer.title == nil)
    }

    /// The account card is the way to the Account page, so it lights where a row would.
    @Test("the account card lights on the Account page and only there")
    func accountCard() {
        #expect(HistoryFixture.sidebar(selection: .page(.account)).isAccountSelected)
        #expect(HistoryFixture.sidebar(selection: .page(.account)).items.allSatisfy { !$0.isSelected })
        #expect(!HistoryFixture.sidebar(selection: .page(.home)).isAccountSelected)
    }

    @Test("every row carries a symbol and a name")
    func everyRowIsDrawable() {
        for item in HistoryFixture.sidebar().items {
            #expect(!item.title.isEmpty)
            #expect(!item.symbolName.isEmpty)
            #expect(item.id == item.destination)
        }
    }

    @Test("the selected row is the only lit one")
    func selection() {
        let items = HistoryFixture.sidebar(selection: .page(.insights)).items
        #expect(items.filter(\.isSelected).map(\.title) == ["Insights"])
    }

    /// Settings is a page of the main window, so its row lights whichever tab it is on.
    @Test("the Settings row lights alone, whichever tab the page is on")
    func settingsLights() {
        for tab in SettingsTab.allCases {
            let items = HistoryFixture.sidebar(selection: .settings(tab)).items
            #expect(items.filter(\.isSelected).map(\.title) == ["Settings"])
        }
    }

    /// And it still lights nothing while a page is showing, rather than lighting both.
    @Test("a page lights its own row and leaves Settings dark")
    func pageLeavesSettingsDark() {
        let items = HistoryFixture.sidebar(selection: .page(.home)).items

        #expect(items.filter(\.isSelected).map(\.title) == ["Home"])
    }

    @Test("the heading over a pane is the same word as its row")
    func titlesMatch() {
        for page in MainTab.allCases {
            #expect(SidebarPresenter.title(for: page) == SidebarPresenter.title(for: .page(page)))
        }
        #expect(SidebarPresenter.title(for: .settings(.general)) == "Settings")
    }
}

@Suite("The corrections badge")
struct SidebarBadgeTests {
    @Test("today's changes are counted on the Dictionary row")
    func badge() {
        let items = HistoryFixture.sidebar(correctionsToday: 7).items
        #expect(items.first { $0.title == "Dictionary" }?.badge == "7")
    }

    /// A badge reading "0" is a badge that has stopped meaning anything.
    @Test("nothing changed means no badge")
    func noBadge() {
        let items = HistoryFixture.sidebar(correctionsToday: 0).items
        #expect(items.allSatisfy { $0.badge == nil })
    }

    @Test(
        "VoiceOver hears the count in the singular when exactly one change was made",
        arguments: [(1, "Dictionary, 1 change today"), (7, "Dictionary, 7 changes today")])
    func spokenCount(changes: Int, expected: String) {
        let items = HistoryFixture.sidebar(correctionsToday: changes).items
        #expect(items.first { $0.title == "Dictionary" }?.accessibilityLabel == expected)
    }

    @Test("a row without a badge is read by its title")
    func spokenTitle() {
        let items = HistoryFixture.sidebar(correctionsToday: 0).items
        #expect(items.allSatisfy { $0.accessibilityLabel == $0.title })
    }

    @Test("no other row is badged")
    func onlyCorrections() {
        let badged = HistoryFixture.sidebar(correctionsToday: 3).items.filter { $0.badge != nil }
        #expect(badged.map(\.title) == ["Dictionary"])
    }
}

@Suite("The sidebar as a whole")
struct SidebarWholeTests {
    @Test("the product is named once")
    func productName() {
        #expect(HistoryFixture.sidebar().productName == "Uttrflow")
        #expect(SidebarPresenter.productName == "Uttrflow")
    }
}
