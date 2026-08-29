import Testing

@testable import UttrflowUX

@Suite("The furniture every page is built out of")
struct MainShellTests {
    @Test("a pill is quiet unless it is told otherwise")
    func pillDefaults() {
        #expect(MainPill(text: "Retired").tone == .neutral)
    }

    @Test("a callout is drawn on the accent unless it is told otherwise")
    func calloutDefaults() {
        #expect(MainCallout(symbolName: "lock", message: "Kept here.").tone == .accent)
    }

    /// Clamped on the way in, so a view can draw a meter without checking and a bad
    /// measurement cannot draw outside its own track.
    @Test("a meter cannot leave its track")
    func meterClamps() {
        #expect(MainMeter(label: "Today", fraction: 1.4).fraction == 1)
        #expect(MainMeter(label: "Today", fraction: -0.2).fraction == 0)
        #expect(MainMeter(label: "Today", fraction: 0.5).fraction == 0.5)
    }

    @Test("a meter is the current figure unless it is the one being compared against")
    func meterBaseline() {
        #expect(!MainMeter(label: "Today", fraction: 0.5).isBaseline)
        #expect(MainMeter(label: "Baseline", fraction: 0.5, isBaseline: true).isBaseline)
        #expect(MainMeter(label: "Today", fraction: 0.5).id == "Today")
    }

    @Test("progress cannot leave its track either")
    func progressClamps() {
        let over = MainProgress(fraction: 9, leading: "9 of 7", trailing: "Soon")
        #expect(over.fraction == 1)
        #expect(MainProgress(fraction: -1, leading: "", trailing: "").fraction == 0)
    }

    /// A pop-up with nothing behind it is a label with a chevron, not a broken menu.
    @Test("a scope with no options is not selectable")
    func scopeSelectability() {
        #expect(!MainScope(title: "Last 7 days").isSelectable)
        #expect(
            MainScope(
                title: "All changes",
                options: [MainScopeOption(id: "all", title: "All changes", isSelected: true)]
            ).isSelectable)
    }

    @Test("a scope option is identified by its own identifier")
    func scopeOptionIdentity() {
        let option = MainScopeOption(id: "undone", title: "Undone", isSelected: false)
        #expect(option.id == "undone")
        #expect(!option.isSelected)
    }

    /// A page that asks for none of the three controls gets a bare heading, which is
    /// what Style and Account are drawn as.
    @Test("a page may have no toolbar at all")
    func bareChrome() {
        let chrome = MainPageChrome(title: "Style")
        #expect(chrome.title == "Style")
        #expect(chrome.scope == nil)
        #expect(chrome.search == nil)
        #expect(chrome.addAction == nil)
    }

    @Test("a search field carries what has been typed as well as the placeholder")
    func searchField() {
        let field = MainSearchField(placeholder: "Search words", query: "uttr")
        #expect(field.placeholder == "Search words")
        #expect(field.query == "uttr")
    }
}
