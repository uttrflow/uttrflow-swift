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
}
