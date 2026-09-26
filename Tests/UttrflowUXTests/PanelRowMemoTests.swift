// Tests that an arrow key rebuilds only the rows whose selection moved, and draws the same rows.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

@Suite("The quick panel: rows are built once per open")
struct PanelRowMemoTests {
    static let clips = (0..<1_000).map { PanelFixture.clip("clip number \($0)", minutesAgo: $0) }

    @Test("an arrow key on a 1,000-clip history builds no row again")
    func arrowBuildsNothing() {
        let panel = PanelFixture.panel(Self.clips)
        _ = PanelPresenter.present(panel)
        let opened = panel.rowMemo.builds
        let arrowed = panel.applying(.down).state
        let page = PanelPresenter.present(arrowed)

        #expect(opened == 1_000)
        #expect(arrowed.rowMemo.builds - opened <= 2)
        #expect(page.rows.filter(\.isSelected).map(\.id) == [Self.clips[1].id])
    }

    @Test("the rows drawn after an arrow key are the rows a fresh panel draws")
    func sameRows() {
        let panel = PanelFixture.panel(Self.clips)
        _ = PanelPresenter.present(panel)
        let arrowed = panel.applying(.down).state
        var fresh = PanelFixture.panel(Self.clips)
        fresh.selection = arrowed.selection

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
