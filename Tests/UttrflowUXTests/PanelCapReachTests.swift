// Tests that the per-group cap never hides a clip that typing more could not reach (#898).
import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

@Suite("Every match can be reached from its query")
struct PanelCapReachTests {
    @Test("a clip whose whole text is the query leads its group past newer clips containing it")
    func wholeTextLeads() {
        let target = PanelFixture.clip("localhost:8080", minutesAgo: 60)
        let newer = (1...6).map {
            PanelFixture.clip("http://localhost:8080/api/v\($0)", kind: .link, minutesAgo: $0)
        }
        let results = PanelFixture.panel(newer + [target], query: "localhost:8080").results
        #expect(results.rows.first?.clip.id == target.id)
    }

    @Test("every picture in a collection named exactly is listed")
    func exactCollectionIsWhole() {
        let receipts = (1...10).map {
            PanelFixture.clip("", kind: .image, minutesAgo: $0, category: "Receipts")
        }
        let results = PanelFixture.panel(receipts, query: "receipts").results
        #expect(results.rows.count == 10)
        #expect(results.omitted.isEmpty)
    }

    @Test("a collection named only in part is still capped, since typing more reaches the rest")
    func partialCollectionIsCapped() {
        let receipts = (1...10).map {
            PanelFixture.clip("", kind: .image, minutesAgo: $0, category: "Receipts")
        }
        let results = PanelFixture.panel(receipts, query: "rece").results
        #expect(results.rows.count == PanelPresenter.rowsPerGroup)
    }
}
