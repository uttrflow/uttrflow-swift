// Tests that an arrow key rebuilds only the rows whose selection moved, and draws the same rows.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

@Suite("The quick panel: rows are built once per open")
struct PanelRowMemoTests {
    static let clips = (0..<5_000).map { PanelFixture.clip("clip number \($0)", minutesAgo: $0) }

    @Test("1,000 arrows on a 5,000-clip history visit no rows again")
    func arrowBuildsNothing() {
        var panel = PanelFixture.panel(Self.clips)
        _ = PanelPresenter.present(panel)
        let opened = panel.rowMemo.builds
        let visited = panel.rowMemo.rowVisits
        let grouped = panel.rowMemo.groupBuilds
        var page = PanelPresenter.present(panel)
        for _ in 0..<1_000 {
            panel = panel.applying(.down).state
            page = PanelPresenter.present(panel)
        }
        #expect(opened == 5_000)
        #expect(panel.rowMemo.rowVisits == visited)
        #expect(panel.rowMemo.groupBuilds == grouped)
        #expect(panel.searchMemo.searchScans == 1)
        #expect(page.rows.filter(\.isSelected).map(\.id) == [Self.clips[1_000].id])
    }

    @Test("a new list refreshes timestamps once, then keystrokes reuse those rows")
    func refreshedRowsStayMemoized() {
        let openedAt = Date(timeIntervalSince1970: 1_000_000)
        let original = Clip(text: "original", kind: .text, copiedAt: openedAt)
        let panel = PanelFixture.panel([original])
        _ = PanelPresenter.present(panel)
        let beforeRefresh = panel.rowMemo.builds
        let copiedAt = openedAt.addingTimeInterval(90)
        let refreshedAt = copiedAt.addingTimeInterval(1)
        let arrived = Clip(text: "just copied", kind: .text, copiedAt: copiedAt)
        var refreshed = panel
        refreshed.install(
            [arrived, original], missingImages: [], formattableLanguages: [], now: refreshedAt)
        _ = PanelPresenter.present(refreshed)
        let afterRefresh = refreshed.rowMemo.builds

        refreshed = refreshed.applying(.down).state
        _ = PanelPresenter.present(refreshed)

        #expect(afterRefresh - beforeRefresh == 2)
        #expect(refreshed.rowMemo.builds == afterRefresh)
    }

    @Test("the rows drawn after an arrow key are the rows a fresh panel draws")
    func sameRows() {
        let panel = PanelFixture.panel(Self.clips)
        let first = PanelPresenter.present(panel)
        let arrowed = panel.applying(.down).state
        var fresh = PanelFixture.panel(Self.clips)
        fresh.selection = arrowed.selection

        #expect(first.selectedRow?.id == Self.clips[0].id)
        #expect(PanelPresenter.present(arrowed).selectedRow?.id == Self.clips[1].id)
        #expect(first.rows.first?.isSelected == true, "an older presentation remains a value snapshot")
        #expect(PanelPresenter.present(arrowed) == PanelPresenter.present(fresh))
    }

    @Test("revealing a secret rebuilds its row")
    func revealRebuilds() {
        let secret = PanelFixture.clip("hunter2", kind: .secret)
        var panel = PanelFixture.panel([secret])
        #expect(PanelPresenter.present(panel).rows[0].isMasked)
        panel.revealed = [secret.id]

        #expect(!PanelPresenter.present(panel).rows[0].isMasked)
    }

    @Test("the relative time reads the same through the shared formatter")
    func when() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let locale = Locale(identifier: "en_US")
        let first = HistoryPresenter.when(now.addingTimeInterval(-120), relativeTo: now, locale: locale)
        let again = HistoryPresenter.when(now.addingTimeInterval(-120), relativeTo: now, locale: locale)

        #expect(first == "2 minutes ago")
        #expect(again == first)
    }
}
