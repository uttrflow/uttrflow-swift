import Foundation
import Testing
import UttrflowPredict

@testable import UttrflowPredictStore

@Suite("Suggestion corpus bounds", .bug(id: 3690))
struct CorpusBoundTests {
    private let surface = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea")

    @Test("A line unused past the support floor is expired, and a recent one stays")
    func expiresAgedLines() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let now = Date()
        try await store.record("old forgotten line", in: surface, at: now.addingTimeInterval(-50 * 86_400))
        try await store.record("recent line here", in: surface, at: now.addingTimeInterval(-40 * 86_400))
        #expect(try await store.expireStale(now: now) == 1)
        #expect(try await store.candidates(for: surface, matching: "old for").isEmpty)
        #expect(try await store.candidates(for: surface, matching: "recent li").count == 1)
    }

    @Test("A stamp far ahead of the clock is hidden, never deleted")
    func keepsUntrustedStamps() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let now = Date()
        try await store.record("kept line here", in: surface, at: now.addingTimeInterval(-50 * 86_400))
        #expect(try await store.expireStale(now: now.addingTimeInterval(400 * 86_400)) == 0)
        #expect(try await store.entryCount() == 1)
    }

    @Test("The whole corpus never exceeds its cap and the new line survives")
    func capsTheStore() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let now = Date()
        let surfaces = (0..<11).map { Surface(bundleIdentifier: "com.example.app\($0)", role: "AXTextArea") }
        for (index, surface) in surfaces.enumerated() {
            for line in 0..<PredictStore.entriesPerSurface {
                try await store.record("line \(index) number \(line) end", in: surface, at: now)
            }
        }
        try await store.record("the newest line", in: surfaces[0], at: now)
        #expect(try await store.entryCount() <= PredictStore.entriesPerStore)
        #expect(try await store.candidates(for: surfaces[0], matching: "the newest").count == 1)
    }
}
