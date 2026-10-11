// Checks externally prepared values against the shared memo storage contract.
import Testing
@testable import UttrflowUX

@Suite("Prepared memo storage")
struct MemoStoreTests {
    @Test("a prepared answer bypasses the builder until its source changes")
    func preparedAnswer() {
        let memo = Memo<Int, String, Int>()
        memo.store(7, for: 1, source: "ready")
        var builds = 0
        func read(_ source: String) -> Int {
            memo.value(for: 1, source: source) {
                builds += 1; return source.count
            }
        }
        #expect(read("ready") == 7)
        #expect(builds == 0)
        #expect(read("changed") == 7)
        #expect(read("changed") == 7)
        #expect(builds == 1)
    }

    @Test("a prepared answer replaces the same source without evicting another key")
    func replacementAtCapacity() {
        let memo = Memo<Int, Int, Int>(limit: 2)
        memo.store(1, for: 1, source: 1)
        memo.store(4, for: 2, source: 2)
        memo.store(9, for: 1, source: 1)
        var builds = 0
        #expect(
            memo.value(for: 1, source: 1) {
                builds += 1; return 0
            } == 9)
        #expect(builds == 0)
        #expect(memo.remembers(2))
        #expect(memo.count == 2)
        memo.store(16, for: 3, source: 3)
        #expect(!memo.remembers(1))
        #expect(!memo.remembers(2))
        #expect(memo.count == 1)
    }
}
