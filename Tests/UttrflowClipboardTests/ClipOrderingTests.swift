// Tests for the ordering rules, which need no store and no files.

import Foundation
import Testing

@testable import UttrflowClipboard

/// The display and eviction order of a list of clips, checked without a store.
@Suite("Clip ordering")
struct ClipOrderingTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func clip(_ text: String, at offset: Double, order: UInt64? = nil, alias: String? = nil) -> Clip {
        Clip(
            text: text, kind: .text, copiedAt: base.addingTimeInterval(offset), lastUsedOrder: order,
            alias: alias)
    }

    /// A higher stored use order is shown first, whatever the copy time says.
    @Test("a higher use order sorts first, over the copy time")
    func useOrderOutranksTime() {
        let older = clip("older", at: 0, order: 9)
        let newer = clip("newer", at: 100, order: 2)
        let sorted = ClipOrdering.orderedForDisplay([newer, older])
        #expect(sorted.map(\.text) == ["older", "newer"])
    }

    /// A clip with a stored order precedes one without, and unnumbered clips fall back to copy time.
    @Test("a numbered clip precedes an unnumbered one, and unnumbered ones go newest first")
    func numberedBeforeUnnumbered() {
        let numbered = clip("numbered", at: 0, order: 1)
        let early = clip("early", at: 10)
        let late = clip("late", at: 20)
        let sorted = ClipOrdering.orderedForDisplay([early, late, numbered])
        #expect(sorted.map(\.text) == ["numbered", "late", "early"])
    }

    /// Clips that tie on every key keep the order they arrived in.
    @Test("a tie keeps arrival order")
    func tieKeepsArrival() {
        let first = clip("first", at: 0, order: 3)
        let second = clip("second", at: 0, order: 3)
        #expect(ClipOrdering.orderedForDisplay([first, second]).map(\.text) == ["first", "second"])
    }

    /// Merging two lists keeps each list's own order and puts the more recently used clip first.
    @Test("interleaving merges two sorted lists newest first")
    func interleavingMerges() {
        let saved = [clip("s1", at: 0, order: 8), clip("s2", at: 0, order: 2)]
        let history = [clip("h1", at: 0, order: 5), clip("h2", at: 0, order: 1)]
        let merged = ClipOrdering.interleaving(saved: saved, history: history)
        #expect(merged.map(\.text) == ["s1", "h1", "s2", "h2"])
    }

    /// Only the first clip holding an alias keeps it.
    @Test("a repeated alias stays only on the first clip")
    func uniqueAliasesKeepsFirst() {
        let list = [clip("a", at: 2, alias: "x"), clip("b", at: 1, alias: "x"), clip("c", at: 0)]
        let result = ClipOrdering.uniqueAliases(in: list)
        #expect(result.map(\.alias) == ["x", nil, nil])
    }

    /// Whole and distinct stored orders are left alone.
    @Test("distinct stored orders are kept as they are")
    func distinctOrdersUntouched() {
        let list = [clip("a", at: 0, order: 4), clip("b", at: 0, order: 7)]
        #expect(ClipOrdering.numberedForEviction(list) == list)
    }

    /// Missing or duplicate orders are renumbered 1...n, oldest use first.
    @Test("missing or repeated orders are renumbered from the oldest use")
    func renumbersWhenIncomplete() {
        let list = [clip("a", at: 20), clip("b", at: 10), clip("c", at: 30, order: 5)]
        let numbered = ClipOrdering.numberedForEviction(list)
        // Unnumbered clips rank below numbered ones, oldest use first: b, then a, then c.
        #expect(numbered.map(\.lastUsedOrder) == [2, 1, 3])
        #expect(Set(numbered.compactMap(\.lastUsedOrder)).count == 3)
        #expect(numbered.map(\.text) == ["a", "b", "c"], "the list order itself is not changed")
    }
}
