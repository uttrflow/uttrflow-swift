// Checks the shared storage contract behind per-clip panel derivations.
import Testing
@testable import UttrflowUX

@Suite("Per-source memo storage")
struct MemoTests {
    @Test("a repeated source builds once, while a changed source replaces its answer")
    func sourceMatching() {
        let memo = Memo<Int, String, Int>()
        var builds = 0
        func read(_ source: String) -> Int {
            memo.value(for: 1, source: source) {
                builds += 1
                return source.count
            }
        }
        #expect(read("alpha") == 5)
        #expect(read("alpha") == 5)
        #expect(builds == 1)
        #expect(read("bravo!") == 6)
        #expect(read("bravo!") == 6)
        #expect(builds == 2)
        #expect(memo.count == 1)
    }

    @Test("a nil result is a remembered answer rather than a miss")
    func nilAnswer() {
        let memo = Memo<Int, String, Int?>()
        var builds = 0
        for _ in 0..<2 {
            let answer = memo.value(for: 1, source: "none") {
                builds += 1
                return nil
            }
            #expect(answer == nil)
        }
        #expect(builds == 1)
        #expect(memo.remembers(1))
    }

    @Test("pruning keeps live answers and rebuilds removed keys")
    func pruning() {
        let memo = Memo<Int, Int, Int>()
        var builds = 0
        func read(_ key: Int) -> Int {
            memo.value(for: key, source: key) {
                builds += 1
                return key * key
            }
        }
        _ = read(2)
        _ = read(3)
        memo.prune(to: [2])
        #expect(read(2) == 4)
        #expect(builds == 2)
        #expect(!memo.remembers(3))
        #expect(read(3) == 9)
        #expect(builds == 3)
    }

    @Test("capacity clears all only when storing a previously absent key")
    func capacity() {
        let memo = Memo<Int, Int, Int>(limit: 2)
        _ = memo.value(for: 1, source: 1) { 1 }
        _ = memo.value(for: 2, source: 2) { 4 }
        _ = memo.value(for: 1, source: 3) { 9 }
        #expect(memo.remembers(2))
        #expect(memo.count == 2)
        _ = memo.value(for: 3, source: 3) { 9 }
        #expect(!memo.remembers(1))
        #expect(!memo.remembers(2))
        #expect(memo.count == 1)
    }

    @Test("nonpositive capacity still retains an existing key on replacement", arguments: [0, -1])
    func nonpositiveCapacity(limit: Int) {
        let memo = Memo<Int, Int, Int>(limit: limit)
        _ = memo.value(for: 1, source: 1) { 1 }
        _ = memo.value(for: 1, source: 2) { 4 }
        #expect(memo.count == 1)
        _ = memo.value(for: 2, source: 2) { 4 }
        #expect(!memo.remembers(1))
        #expect(memo.remembers(2))
    }

    @Test("a miss builds outside the lock and stores even after pruning during the build")
    func builderOutsideLock() {
        let memo = Memo<Int, Int, Int>()
        let answer = memo.value(for: 2, source: 2) {
            memo.prune(to: [])
            return 2 * 2
        }
        #expect(answer == 4)
        #expect(memo.remembers(2))
    }
    @Test("a later store wins without changing a miss's local return")
    func interleavedStores() {
        let memo = Memo<Int, String, Int>()
        let first = memo.value(for: 1, source: "outer") {
            let second = memo.value(for: 1, source: "inner") { "inner".count }
            #expect(second == 5)
            return "outer!".count
        }
        #expect(first == 6)
        var rebuilds = 0
        #expect(
            memo.value(for: 1, source: "outer") {
                rebuilds += 1; return 0
            } == 6)
        #expect(rebuilds == 0)
    }

}
