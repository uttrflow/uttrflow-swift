// Tests that grouping search results costs the length of the list, so arrows stay quick over a big collection.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

@Suite("Grouping search results is linear")
struct PanelGroupsCostTests {
    @Test("an exactly named collection of three thousand clips comes back whole, in one group")
    func wholeCollectionIsOneGroup() {
        let clips = (0..<3_000).map { PanelFixture.clip("clip \($0)", minutesAgo: $0, category: "work") }

        let page = PanelPresenter.present(PanelFixture.panel(clips, query: "work"))

        #expect(page.groups.count == 1)
        #expect(page.groups.first?.rows.count == 3_000)
        #expect(page.groups.flatMap(\.rows).map(\.id) == page.rows.map(\.id))
    }

    @Test("forty thousand rows of one kind group into one group")
    func longRunIsOneGroup() {
        let clips = (0..<400).map { PanelFixture.clip("clip \($0)", minutesAgo: $0, category: "work") }
        let rows = PanelPresenter.present(PanelFixture.panel(clips, query: "work")).rows
        let many = Array(repeatElement(rows, count: 100).joined())

        let groups = PanelPresenter.groups(for: many, omitted: [:], isSearching: true)

        #expect(groups.count == 1)
        #expect(groups.first?.rows.count == 40_000)
    }

    /// A quadratic build copies two hundred million rows here, which takes far longer than the bound; it runs in `make bench`.
    @Test("forty thousand rows of one kind group well inside a second")
    func longRunIsLinear() {
        let clips = (0..<400).map { PanelFixture.clip("clip \($0)", minutesAgo: $0, category: "work") }
        let rows = PanelPresenter.present(PanelFixture.panel(clips, query: "work")).rows
        let many = Array(repeatElement(rows, count: 100).joined())

        let clock = ContinuousClock()
        let took = clock.measure {
            _ = PanelPresenter.groups(for: many, omitted: [:], isSearching: true)
        }

        #expect(took < .seconds(1))
    }

    @Test("runs that alternate stay separate groups in order")
    func alternatingRuns() {
        let clips = [
            PanelFixture.clip("one", minutesAgo: 1, alias: "prod"),
            PanelFixture.clip("two", minutesAgo: 2, category: "prod"),
            PanelFixture.clip("the prod box", minutesAgo: 3),
        ]
        let rows = PanelPresenter.present(PanelFixture.panel(clips, query: "prod")).rows

        let groups = PanelPresenter.groups(for: rows, omitted: [.content: 4], isSearching: true)

        #expect(groups.map(\.field) == [.alias, .category, .content])
        #expect(groups.map(\.rows.count) == [1, 1, 1])
        #expect(groups.last?.more == 4)
    }
}
