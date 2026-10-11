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

    @Test("two panels presented in turn share the one cache bound to the task")
    func panelsShareTheBoundCache() {
        let first = PanelFixture.panel([PanelFixture.clip("alpha", minutesAgo: 1)])
        _ = PanelPresenter.present(first)
        let scans = PanelCache.current.searchMemo.searchScans
        _ = PanelPresenter.present(first)
        #expect(PanelCache.current.searchMemo.searchScans == scans)
    }
}
