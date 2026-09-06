import Foundation
import Testing

@testable import UttrflowPredict

/// One key, so a test says what it is varying rather than repeating what it is not.
private func key(_ candidate: String, _ context: String = "terminal") -> VerdictCache.Key {
    VerdictCache.Key(candidate: candidate, context: context)
}

/// A moment far enough past the cache's lifetime that nothing recorded at `moment` survives it.
private let later = moment.addingTimeInterval(VerdictCache.lifetimeInSeconds + 1)

@Suite("Verdicts already reached")
struct VerdictCacheTests {
    @Test("A verdict comes back for the candidate and context that produced it.")
    func remembers() {
        var cache = VerdictCache()
        cache.remember(.attested, for: key("git commit"), now: moment)
        #expect(cache.verdict(for: key("git commit"), now: moment) == .attested)
    }

    @Test("The same candidate in another context is a different question.")
    func contextIsPartOfTheKey() {
        var cache = VerdictCache()
        cache.remember(.attested, for: key("git commit", "terminal"), now: moment)
        #expect(cache.verdict(for: key("git commit", "editor"), now: moment) == nil)
    }

    @Test("Another candidate in the same context is a different question too.")
    func candidateIsPartOfTheKey() {
        var cache = VerdictCache()
        cache.remember(.attested, for: key("git commit"), now: moment)
        #expect(cache.verdict(for: key("git checkout"), now: moment) == nil)
    }

    @Test("A verdict stops being believed once its lifetime has passed.")
    func expires() {
        var cache = VerdictCache()
        cache.remember(.corrected("git commit"), for: key("git comit"), now: moment)
        #expect(cache.verdict(for: key("git comit"), now: later) == nil)
    }

    @Test("Remembering again discards what has expired rather than spending capacity on it.")
    func expiredEntriesAreDropped() {
        var cache = VerdictCache()
        cache.remember(.attested, for: key("git commit"), now: moment)
        #expect(cache.count == 1)
        cache.remember(.attested, for: key("git checkout"), now: later)
        #expect(cache.count == 1)
    }

    @Test("Remembering the same key again replaces the verdict rather than growing the cache.")
    func replacesInPlace() {
        var cache = VerdictCache()
        cache.remember(.plausible, for: key("git comit"), now: moment)
        cache.remember(.corrected("git commit"), for: key("git comit"), now: moment)
        #expect(cache.count == 1)
        #expect(cache.verdict(for: key("git comit"), now: moment) == .corrected("git commit"))
    }

    @Test("Past capacity the oldest verdict is dropped and the newest is kept.")
    func evictsTheOldest() {
        var cache = VerdictCache()
        for index in 0...VerdictCache.capacity {
            cache.remember(.attested, for: key("candidate \(index)"), now: moment)
        }
        #expect(cache.count == VerdictCache.capacity)
        #expect(cache.verdict(for: key("candidate 0"), now: moment) == nil)
        #expect(cache.verdict(for: key("candidate \(VerdictCache.capacity)"), now: moment) == .attested)
    }

    @Test("Forgetting everything leaves nothing behind.")
    func forgets() {
        var cache = VerdictCache()
        cache.remember(.attested, for: key("git commit"), now: moment)
        cache.forgetEverything()
        #expect(cache.count == 0)
        #expect(cache.verdict(for: key("git commit"), now: moment) == nil)
    }
}
