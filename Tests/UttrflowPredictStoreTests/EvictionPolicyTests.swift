import Foundation
import Testing
import UttrflowPredict

@testable import UttrflowPredictStore

@Suite("Suggestion corpus eviction", .bug(id: 5258))
struct EvictionPolicyTests {
    @Test("A newly recorded accepted line survives while an older unaccepted line is evicted")
    func newAcceptedLineSurvivesFullSurface() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let surface = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea")
        let oldest = Date(timeIntervalSince1970: 1_600_000_000)
        let recent = Date(timeIntervalSince1970: 1_700_000_000)
        let newLine = "newly accepted line"
        let previous = "shared previous line"

        try await store.record("old unaccepted sentinel", in: surface, after: previous, at: oldest)
        try await store.record("old unaccepted sentinel", in: surface, after: previous, at: oldest)
        for index in 0..<(PredictStore.entriesPerSurface - 1) {
            let line = "filler line \(index) end"
            try await store.record(line, in: surface, after: previous, at: recent)
            try await store.record(line, in: surface, after: previous, at: recent)
        }

        try await store.record(newLine, in: surface, after: previous, at: recent.addingTimeInterval(1))
        #expect(try successionCount(previous, newLine, corpus: corpus) == 1)
        #expect(try successionCount(previous, "old unaccepted sentinel", corpus: corpus) == 0)
        try await store.recordAccepted(newLine, in: surface)
        try await store.record(
            "trigger line", in: surface, after: previous, at: recent.addingTimeInterval(2))

        let accepted = try await store.candidates(for: surface, matching: "newly accepted")
        #expect(accepted.first?.text == newLine)
        #expect(accepted.first?.evidence?.accepted == 1)
        #expect(try await store.candidates(for: surface, matching: "old unaccepted sentinel").isEmpty)
        #expect(try await store.entryCount() == PredictStore.entriesPerSurface)
    }

    private func successionCount(_ previous: String, _ next: String, corpus: borrowing Corpus) throws -> Int {
        try Database(path: corpus.path).rows(
            """
            SELECT COUNT(*) FROM succession
            JOIN surface ON surface.id = succession.surface_id
            WHERE surface.bundle_id = ? AND surface.role = ?
              AND succession.previous = ? AND succession.next = ?
            """,
            {
                $0.bind(1, "com.example.editor")
                $0.bind(2, "AXTextArea")
                $0.bind(3, previous)
                $0.bind(4, next)
            }
        ) { $0.integer(0) }.first ?? 0
    }

}
