// Tests that the panel's memos live in the panel cache and a snapshot holds state alone.
import Testing
import UttrflowClipboard

@testable import UttrflowUX

@Suite("The quick panel: memos live outside the snapshot", OwnPanelCache())
struct PanelCacheTests {
    @Test("a snapshot stores no reference-type cache")
    func snapshotHoldsNoCaches() {
        let panel = PanelFixture.panel([PanelFixture.clip("one", minutesAgo: 1)])
        let held = Mirror(reflecting: panel).children.filter { child in
            type(of: child.value) is AnyClass && !(child.value is PanelClipListRevision)
        }
        #expect(held.map(\.label).isEmpty)
    }

    @Test("a search answer survives closing and reopening the panel on the same list")
    func searchSurvivesReopen() {
        let clips = (0..<20).map { PanelFixture.clip("clip \($0)", minutesAgo: $0) }
        let cache = PanelCache.current
        let panel = PanelFixture.panel(clips)
        _ = PanelPresenter.present(panel)
        _ = PanelPresenter.present(panel)
        #expect(cache.searchMemo.searchScans == 1)
    }

    @Test("a re-indent answer survives closing and reopening the panel on the same list")
    func reindentSurvivesReopen() {
        let code = Clip(
            text: "func f() {\n\tlet x = 1\n        let y = 2\n}", kind: .code, copiedAt: PanelFixture.now)
        let cache = PanelCache.current
        let first = PanelPresenter.present(PanelFixture.opened([code]).applying(.search("f")).state)
        #expect(first.rows.first?.actions.contains { $0.title == "Re-indent" } == true)
        #expect(cache.reindentOffers.remembers(code.id))

        // Opened the way the app opens it, so the list install that prunes the cache runs again.
        let reopened = PanelFixture.opened([code]).applying(.search("f")).state
        #expect(cache.reindentOffers.remembers(code.id))
        let second = PanelPresenter.present(reopened)
        #expect(second.rows.first?.actions.contains { $0.title == "Re-indent" } == true)
        #expect(cache.reindentOffers.count == 1)
    }

    @Test("a panel presented with a cache passed in works out everything in that cache")
    func presentUsesThePassedCache() {
        let code = Clip(
            text: "func f() {\n\tlet x = 1\n        let y = 2\n}", kind: .code, copiedAt: PanelFixture.now)
        let panel = PanelFixture.panel([code]).applying(.search("f")).state
        let bound = PanelCache.current
        let scans = bound.searchMemo.searchScans
        let builds = bound.rowMemo.builds
        let passed = PanelCache()

        let rows = PanelPresenter.present(panel, using: passed).rows

        #expect(rows.first?.actions.contains { $0.title == "Re-indent" } == true)
        #expect(passed.searchMemo.searchScans == 1)
        #expect(passed.rowMemo.builds == 1)
        #expect(passed.reindentOffers.remembers(code.id))
        #expect(bound.searchMemo.searchScans == scans)
        #expect(bound.rowMemo.builds == builds)
        #expect(!bound.reindentOffers.remembers(code.id))
    }

    @Test("a search presented with a cache passed in folds clip text in that cache")
    func searchFoldsInThePassedCache() {
        let clip = PanelFixture.clip("needle in text", minutesAgo: 1)
        let panel = PanelFixture.panel([clip]).applying(.search("text")).state
        let bound = PanelCache.current
        bound.foldedTexts.prune(to: [])
        let passed = PanelCache()

        _ = PanelPresenter.present(panel, using: passed)

        #expect(passed.foldedTexts.remembers(clip.id))
        #expect(!bound.foldedTexts.remembers(clip.id))
    }

    @Test("a note's checklist count is kept in the cache passed in")
    func checklistCountsInThePassedCache() {
        let note = Clip(
            text: "Shopping list", kind: .text, copiedAt: PanelFixture.now,
            richText: "<ul><li class=\"checked\">Milk</li><li class=\"unchecked\">Tea</li></ul>")
        let panel = PanelFixture.panel([note])
        let passed = PanelCache()

        let rows = PanelPresenter.present(panel, using: passed).rows

        #expect(rows.first?.checklist == "1 of 2")
        #expect(passed.checklistProgresses.remembers(note.id))
        #expect(!PanelCache.current.checklistProgresses.remembers(note.id))
    }

    @Test("a formatting sheet is drawn in the cache passed in")
    func formattingSheetInThePassedCache() {
        let code = Clip(
            text: "func a(){\nlet x=1\n}", kind: .code, copiedAt: PanelFixture.now, language: .swift)
        let formatted = "func a() {\n    let x = 1\n}"
        var panel = PanelFixture.panel([code])
        panel.sheet = .formatting(code.id, formatted: formatted)
        let passed = PanelCache()

        #expect(PanelPresenter.present(panel, using: passed).sheet != nil)
        #expect(passed.formattingSheets.remembers(from: code.text, to: formatted))
        #expect(!PanelCache.current.formattingSheets.remembers(from: code.text, to: formatted))
    }

    @Test("two panels presented in turn share the one cache bound to the task")
    func panelsShareTheBoundCache() {
        let first = PanelFixture.panel([PanelFixture.clip("alpha", minutesAgo: 1)])
        _ = PanelPresenter.present(first)
        let scans = PanelCache.current.searchMemo.searchScans
        _ = PanelPresenter.present(first)
        #expect(PanelCache.current.searchMemo.searchScans == scans)
    }
}
