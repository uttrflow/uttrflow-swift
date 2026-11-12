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

        try await store.record("old unaccepted sentinel", in: surface, at: oldest)
        try await store.record("old unaccepted sentinel", in: surface, at: oldest)
        for index in 0..<(PredictStore.entriesPerSurface - 1) {
            let line = "filler line \(index) end"
            try await store.record(line, in: surface, at: recent)
            try await store.record(line, in: surface, at: recent)
        }

        try await store.record(newLine, in: surface, at: recent.addingTimeInterval(1))
        try await store.recordAccepted(newLine, in: surface)
        try await store.record("trigger line", in: surface, at: recent.addingTimeInterval(2))

        let accepted = try await store.candidates(for: surface, matching: "newly accepted")
        #expect(accepted.first?.text == newLine)
        #expect(accepted.first?.evidence?.accepted == 1)
        #expect(try await store.candidates(for: surface, matching: "old unaccepted sentinel").isEmpty)
        #expect(try await store.entryCount() == PredictStore.entriesPerSurface)
    }
}
