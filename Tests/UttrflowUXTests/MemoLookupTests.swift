// Checks source-sensitive reads without rebuilding the shared panel memo.
import Testing

@testable import UttrflowUX

@Suite("Source-sensitive memo lookup")
struct MemoLookupTests {
    @Test("an absent key remains absent after a lookup")
    func missingKey() {
        let memo = Memo<Int, String, Int>()
        #expect(memo.cachedValue(for: 1, source: "first") == nil)
        #expect(memo.count == 0)
    }

    @Test("a changed source misses without replacing the matching answer")
    func sourceMatching() {
        let memo = Memo<Int, String, Int>()
        memo.store(7, for: 1, source: "first")
        #expect(memo.cachedValue(for: 1, source: "other") == nil)
        #expect(memo.cachedValue(for: 1, source: "first") == 7)
        #expect(memo.count == 1)
    }

    @Test("a stored nil remains distinguishable from an absent answer")
    func storedNil() {
        let memo = Memo<Int, String, Int?>()
        memo.store(nil, for: 1, source: "first")
        let hit = memo.cachedValue(for: 1, source: "first")
        #expect(hit != nil)
        #expect(hit.flatMap { $0 } == nil)
        #expect(memo.cachedValue(for: 1, source: "other") == nil)
        #expect(memo.cachedValue(for: 2, source: "first") == nil)
    }

    @Test("a cached nil bypasses the builder through the shared lookup")
    func nilBypassesBuild() {
        let memo = Memo<Int, String, Int?>()
        memo.store(nil, for: 1, source: "first")
        var builds = 0
        let answer = memo.value(for: 1, source: "first") {
            builds += 1
            return 9
        }
        #expect(answer == nil)
        #expect(builds == 0)
    }
}
