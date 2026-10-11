// Tests the distance and recall arithmetic behind the name-reach table, on invented editor text.
import Testing

@testable import UttrflowEval

@Suite("Name reach")
struct NameReachTests {
    private let filler = String(repeating: "x ", count: 200)

    @Test("The distance runs from the start of the nearest whole token to the caret")
    func distanceToNearest() {
        let before = "let ledger_total = 1\nlet ledger_total = 2\n"
        #expect(NameReach.distance(of: "ledger_total", in: before) == 17)
    }

    @Test("A name inside a longer identifier does not count")
    func partialTokenIgnored() {
        #expect(NameReach.distance(of: "total", in: "let ledger_total = 1") == nil)
        #expect(NameReach.distance(of: "ledger", in: "let ledger_total = 1") == nil)
    }

    @Test("A name that never appears has no distance")
    func absent() {
        #expect(NameReach.distance(of: "orbit", in: "let ledger = 1") == nil)
        #expect(NameReach.distance(of: "", in: "let ledger = 1") == nil)
        #expect(NameReach.distance(of: "ledger", in: "") == nil)
    }

    @Test("Recall rises with the window")
    func recallRises() {
        let near = NameReach.Session(before: "struct Basket {}\n" + filler, dictated: ["Basket"])
        let far = NameReach.Session(
            before: "struct Quarry {}\n" + String(repeating: filler, count: 4), dictated: ["Quarry"])
        let sessions = [near, far]
        #expect(NameReach.recall(sessions, window: 300) == 0)
        #expect(NameReach.recall(sessions, window: 1_000) == 0.5)
        #expect(NameReach.recall(sessions, window: 4_000) == 1)
    }

    @Test("A name cut by the window's start is not found")
    func windowStartingMidToken() {
        let session = NameReach.Session(before: "Basket " + "y", dictated: ["Basket"])
        #expect(NameReach.recall([session], window: 7) == 0)
        #expect(NameReach.recall([session], window: 8) == 1)
    }

    @Test("No dictated names gives no recall")
    func noNames() {
        #expect(NameReach.recall([], window: 300) == nil)
    }
}
