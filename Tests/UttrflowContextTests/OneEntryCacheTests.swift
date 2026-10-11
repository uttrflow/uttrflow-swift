import Testing

@testable import UttrflowContext

@Suite("One focused-field cache entry")
struct OneEntryCacheTests {
    private struct Key: Equatable, Sendable {
        let process: Int
        let element: Int
        let window: Int
    }

    @Test("Stable answers are reused only for the same process, element and window")
    func identityScopesTheCachedAnswers() {
        let cache = OneEntryCache<Key, String>()
        let field = Key(process: 42, element: 7, window: 3)
        cache.insert("answers", for: field)

        #expect(cache.value(for: field) == "answers")
        #expect(cache.value(for: Key(process: 43, element: 7, window: 3)) == nil)
        #expect(cache.value(for: field) == nil)
    }

    @Test("A focused element or its window changing evicts the previous answers")
    func focusAndWindowChangesEvict() {
        let cache = OneEntryCache<Key, String>()
        let field = Key(process: 42, element: 7, window: 3)
        cache.insert("answers", for: field)

        #expect(cache.value(for: Key(process: 42, element: 8, window: 3)) == nil)
        cache.insert("answers", for: field)
        #expect(cache.value(for: Key(process: 42, element: 7, window: 4)) == nil)
    }

    @Test("Answers read before a clear are not kept after it")
    func insertBegunBeforeAClearIsDropped() {
        let cache = OneEntryCache<Key, String>()
        let field = Key(process: 42, element: 7, window: 3)
        let before = cache.generation
        cache.clear()

        #expect(!cache.insert("old frame", for: field, readSince: before))
        #expect(cache.value(for: field) == nil)
        #expect(cache.insert("new frame", for: field, readSince: cache.generation))
        #expect(cache.value(for: field) == "new frame")
    }
}
