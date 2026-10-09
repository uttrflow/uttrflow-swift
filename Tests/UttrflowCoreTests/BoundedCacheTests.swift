import Foundation
import Testing

@testable import UttrflowCore

@Suite("A bounded cache")
struct BoundedCacheTests {
    @Test("A stored value comes back for its key and no other.")
    func storesAndReads() {
        var cache = BoundedCache<String, Int>(capacity: 4)
        cache.store(1, for: "one")
        #expect(cache.value(for: "one") == 1)
        #expect(cache.value(for: "two") == nil)
    }

    @Test("Past capacity the least recently used entry is dropped, and a read counts as use.")
    func evictsLeastRecentlyUsed() {
        var cache = BoundedCache<String, Int>(capacity: 2)
        cache.store(1, for: "one")
        cache.store(2, for: "two")
        #expect(cache.value(for: "one") == 1)
        cache.store(3, for: "three")
        #expect(cache.count == 2)
        #expect(cache.value(for: "two") == nil)
        #expect(cache.value(for: "one") == 1)
        #expect(cache.value(for: "three") == 3)
    }

    @Test("Storing a key again replaces its value and makes it the most recently used.")
    func replacesInPlace() {
        var cache = BoundedCache<String, Int>(capacity: 2)
        cache.store(1, for: "one")
        cache.store(2, for: "two")
        cache.store(10, for: "one")
        cache.store(3, for: "three")
        #expect(cache.count == 2)
        #expect(cache.value(for: "one") == 10)
        #expect(cache.value(for: "two") == nil)
    }

    @Test("An entry stops being believed once its lifetime has passed, and the next store sweeps it.")
    func expires() {
        var cache = BoundedCache<String, Int>(capacity: 4, lifetime: .seconds(5))
        let now = ContinuousClock.now
        cache.store(1, for: "one", now: now)
        #expect(cache.value(for: "one", now: now + .seconds(4)) == 1)
        #expect(cache.value(for: "one", now: now + .seconds(6)) == nil)
        cache.store(2, for: "two", now: now + .seconds(6))
        #expect(cache.count == 1)
    }

    @Test("Removing one key and forgetting everything leave the chain usable.")
    func removesAndForgets() {
        var cache = BoundedCache<Int, Int>(capacity: 3)
        for index in 0..<3 { cache.store(index, for: index) }
        cache.remove(1)
        #expect(cache.count == 2)
        cache.store(3, for: 3)
        cache.store(4, for: 4)
        #expect(cache.value(for: 0) == nil)
        cache.forgetEverything()
        #expect(cache.count == 0)
        cache.store(5, for: 5)
        #expect(cache.value(for: 5) == 5)
    }

    @Test("A capacity of zero holds nothing.")
    func zeroCapacity() {
        var cache = BoundedCache<Int, Int>(capacity: 0)
        cache.store(1, for: 1)
        #expect(cache.count == 0)
    }

    @Test("Many uses stay within capacity and keep exactly the most recent keys.")
    func manyUses() {
        var cache = BoundedCache<Int, Int>(capacity: 8)
        for index in 0..<1_000 {
            cache.store(index, for: index % 13)
            _ = cache.value(for: (index * 7) % 13)
        }
        #expect(cache.count == 8)
    }

    /// The files that hold a bounded cache, written out so a new holder has to be seen.
    private static let holders: Set<String> = [
        "UttrflowLocalModel/JudgementCache.swift", "UttrflowPredict/VerdictCache.swift",
    ]

    @Test("Every bounded cache is listed here and its holder forgets it on the reset path.")
    func everyCacheIsForgotten() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // UttrflowCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appending(path: "Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var found: Set<String> = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let relative = String(url.path.dropFirst(sources.path.count + 1))
            guard relative != "UttrflowCore/Support/BoundedCache.swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            guard text.contains("BoundedCache<") else { continue }
            found.insert(relative)
            #expect(text.contains(".forgetEverything()"), "\(relative) never forgets its cache")
        }
        #expect(found == Self.holders)
    }
}
