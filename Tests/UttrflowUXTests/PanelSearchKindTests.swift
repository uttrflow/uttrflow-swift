// Tests that a search keeps the kind chip and says so when it finds nothing (#899).
import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

@Suite("A search under a kind chip")
struct PanelSearchKindTests {
    static let link = Clip(
        text: "https://example.com/invoice/42", kind: .link, copiedAt: PanelFixture.now)
    static let code = Clip(text: "let x = 1", kind: .code, copiedAt: PanelFixture.now)

    @Test("with Code chosen, an empty search names Code and the way to widen it")
    func emptySearchNamesTheChip() {
        let snapshot = PanelFixture.panel([Self.link, Self.code])
            .applying([.filter(.code), .search("invoice")]).state
        let page = PanelPresenter.present(snapshot)
        #expect(snapshot.results.rows.isEmpty)
        #expect(page.filters.filter(\.isActive).map(\.title) == ["Code"])
        #expect(
            page.emptyState?.message
                == "Nothing under Code mentions “invoice”. Choose All to search everything.")
    }

    @Test("with All chosen, the same search finds the link")
    func allFindsIt() {
        let snapshot = PanelFixture.panel([Self.link, Self.code]).applying(.search("invoice")).state
        #expect(snapshot.results.rows.map(\.clip.id) == [Self.link.id])
    }

    @Test("with All chosen, a search that finds nothing speaks for the whole clipboard")
    func nothingAnywhere() {
        let snapshot = PanelFixture.panel([Self.link, Self.code]).applying(.search("zebra")).state
        #expect(
            PanelPresenter.present(snapshot).emptyState?.message
                == "Nothing on your clipboard mentions “zebra”.")
    }
}
