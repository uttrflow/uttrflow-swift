import Foundation
import UttrflowSettings
import Testing

@testable import UttrflowUX

extension HistoryFixture {
    static func sidebar(
        selection: SidebarDestination = .page(.dictation),
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

@Suite("The sidebar's ten destinations")
struct SidebarOrderTests {
    /// The order the design puts them in, pinned. Settings sits ninth even though it is
    /// not a page, and tidying the list would rearrange the window.
    @Test("the rows are in the designed order")
    func order() {
        #expect(
            HistoryFixture.sidebar().items.map(\.title) == [
                "Home", "Dictation", "History", "Dictionary", "Corrections", "Insights", "Snippets",
                "Style", "Diagnostics", "Settings", "Account",
            ])
    }

    @Test("every page in the window is reachable from the sidebar")
    func everyPageIsReachable() {
        let reached = HistoryFixture.sidebar().items.compactMap { item -> MainTab? in
            guard case .page(let page) = item.destination else { return nil }
            return page
        }
        #expect(Set(reached) == Set(MainTab.allCases))
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

    /// Settings is a window rather than a page, and the rail is the main window's own
    /// navigation. Lighting its row said the reader was somewhere they were not: the row
    /// stayed lit for as long as the Settings window existed anywhere on the desktop,
    /// including behind the main window, so Home could be open with Settings highlighted
    /// beside it.
    @Test("the Settings row never lights, whichever tab that window is on")
    func settingsNeverLights() {
        for tab in SettingsTab.allCases {
            let items = HistoryFixture.sidebar(selection: .settings(tab)).items
            #expect(items.filter(\.isSelected).isEmpty)
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
    @Test("today's changes are counted on the Corrections row")
    func badge() {
        let items = HistoryFixture.sidebar(correctionsToday: 7).items
        #expect(items.first { $0.title == "Corrections" }?.badge == "7")
    }

    /// A badge reading "0" is a badge that has stopped meaning anything.
    @Test("nothing changed means no badge")
    func noBadge() {
        let items = HistoryFixture.sidebar(correctionsToday: 0).items
        #expect(items.allSatisfy { $0.badge == nil })
    }

    @Test("no other row is badged")
    func onlyCorrections() {
        let badged = HistoryFixture.sidebar(correctionsToday: 3).items.filter { $0.badge != nil }
        #expect(badged.map(\.title) == ["Corrections"])
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
