import Foundation
import Testing

@testable import Uttrflow

@MainActor
@Suite("Suggestion model cache removal")
struct SuggestionModelCacheOperationsTests {
    @Test("waits for model release before deleting its files")
    func removalWaitsForModelRelease() async throws {
        let (events, record) = AsyncStream<String>.makeStream()
        let operations = SuggestionModelCacheOperations(
            release: { record.yield("released") },
            readBytes: { nil },
            removeFiles: { record.yield("removed") })
        operations.configure(
            stopModel: { Task { await operations.releaseModel() } },
            onCacheChange: {})

        try await operations.removeCachedFiles()
        var order: [String] = []
        for await event in events.prefix(2) { order.append(event) }
        #expect(order == ["released", "removed"])
    }

    @Test("releases the model itself when nothing else stops it, then clears the cached size")
    func removalReleasesTheModelWhenNoStopIsConfigured() async throws {
        let (events, record) = AsyncStream<String>.makeStream()
        let operations = SuggestionModelCacheOperations(
            release: { record.yield("released") },
            readBytes: { 42 },
            removeFiles: { record.yield("removed") })

        try await operations.removeCachedFiles()
        var order: [String] = []
        for await event in events.prefix(2) { order.append(event) }
        #expect(order == ["released", "removed"])
        #expect(operations.cachedBytesOnDisk == 0)
        #expect(!operations.isRemovingCache)
    }

    @Test("a removal that fails is reported to the caller and leaves the cache size alone")
    func failedRemovalIsReported() async {
        struct Refused: Error {}
        let operations = SuggestionModelCacheOperations(
            release: nil, readBytes: { 7 }, removeFiles: { throw Refused() })
        var reported: (any Error)?

        await operations.removeCachedFiles(onFailure: { reported = $0 }).value

        #expect(reported is Refused)
        #expect(operations.cachedBytesOnDisk == nil)
        #expect(!operations.isRemovingCache)
    }

    @Test("a removal that works reports no failure")
    func successfulRemovalReportsNothing() async {
        let operations = SuggestionModelCacheOperations(
            release: nil, readBytes: { 7 }, removeFiles: {})
        var reported = false

        await operations.removeCachedFiles(onFailure: { _ in reported = true }).value

        #expect(!reported)
        #expect(operations.cachedBytesOnDisk == 0)
    }

    @Test("probing the cache reads its size once and tells the owner")
    func probeReadsTheSize() async {
        let operations = SuggestionModelCacheOperations(
            release: nil, readBytes: { 1_234 }, removeFiles: nil)
        let (changes, notify) = AsyncStream<Void>.makeStream()
        operations.configure(stopModel: { nil }, onCacheChange: { notify.yield() })

        operations.probeCache()
        for await _ in changes.prefix(1) {}

        #expect(operations.cachedBytesOnDisk == 1_234)
    }
}
