import Foundation
import Testing

@testable import UttrflowUX

@Suite("Panel search history retains its identity and eviction order")
struct PanelSearchHistoryTests {
    @Test("a hit promotes the oldest query before the next insertion evicts its successor")
    func recentEviction() {
        let memo = PanelSearchMemo()
        var panel = PanelFixture.panel([PanelFixture.clip("alpha")])
        let identities = (0..<PanelSearchMemo.depth).map { index in
            panel.query = "query \(index)"
            return read(panel, through: memo)
        }
        #expect(memo.searchScans == PanelSearchMemo.depth)
        panel.query = "query 0"
        #expect(read(panel, through: memo) == identities[0])
        #expect(memo.searchScans == PanelSearchMemo.depth)
        panel.query = "query \(PanelSearchMemo.depth)"
        _ = read(panel, through: memo)
        panel.query = "query 0"
        #expect(read(panel, through: memo) == identities[0])
        panel.query = "query \(PanelSearchMemo.depth - 1)"
        #expect(read(panel, through: memo) == identities[PanelSearchMemo.depth - 1])
        #expect(memo.searchScans == PanelSearchMemo.depth + 1)
        panel.query = "query 1"
        #expect(read(panel, through: memo) != identities[1])
        #expect(memo.searchScans == PanelSearchMemo.depth + 2)
    }

    @Test("a locale change has its own answer without losing the earlier locale")
    func localeIdentity() {
        let memo = PanelSearchMemo()
        let original = PanelFixture.panel([PanelFixture.clip("alpha")], query: "alpha")
        let first = read(original, through: memo)
        var changed = original
        changed.locale = Locale(identifier: "tr_TR")
        #expect(read(changed, through: memo) != first)
        #expect(read(original, through: memo) == first)
        #expect(memo.searchScans == 2)
    }

    @Test("revealed identities have their own answer without losing the earlier view")
    func revealedIdentity() {
        let memo = PanelSearchMemo()
        let clip = PanelFixture.clip("alpha")
        let original = PanelFixture.panel([clip], query: "alpha")
        let first = read(original, through: memo)
        var changed = original
        changed.revealed = [clip.id]
        #expect(read(changed, through: memo) != first)
        #expect(read(original, through: memo) == first)
        #expect(memo.searchScans == 2)
    }

    @Test("a clip revision drops earlier answers even when the old view returns")
    func revisionForgets() {
        let memo = PanelSearchMemo()
        let original = PanelFixture.panel([PanelFixture.clip("alpha")], query: "alpha")
        let first = read(original, through: memo)
        var changed = original
        changed.clips = [PanelFixture.clip("beta")]
        _ = read(changed, through: memo)
        #expect(read(original, through: memo) != first)
        #expect(memo.searchScans == 3)
    }

    private func read(_ panel: PanelSnapshot, through memo: PanelSearchMemo) -> UUID {
        memo.rows(
            for: PanelSearchMemo.View(panel), scanning: panel.matches(ruledIn:), ranking: panel.ranked
        ).2
    }
}
