import Foundation
import Testing
import UttrflowPredict

@testable import UttrflowPredictStore

@Suite("Suggestion corpus counts")
struct PredictStoreCountsTests {
    @Test("the corpus totals its stored entries and suggestion outcomes across surfaces")
    func countsStoredEvidence() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let terminal = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea")
        let editor = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea")
        let moment = Date(timeIntervalSince1970: 1_800_000_000)

        try await store.record("typed line", in: terminal, at: moment)
        try await store.record("accepted line", in: terminal, selfSourced: true, at: moment)
        try await store.record("another line", in: editor, at: moment)
        try await store.recordAccepted("accepted line", in: terminal)
        try await store.recordRejected("typed line", in: terminal)

        let counts = try await store.corpusCounts()
        #expect(counts.entries == 3)
        #expect(counts.uses == 3)
        #expect(counts.accepted == 1)
        #expect(counts.rejected == 1)
        #expect(counts.selfSourced == 1)
    }

    @Test("an empty corpus reports zero counts")
    func emptyCounts() async throws {
        let corpus = Corpus()
        let counts = try await store(corpus).corpusCounts()

        #expect(
            counts == PredictionCorpusCounts(entries: 0, uses: 0, accepted: 0, rejected: 0, selfSourced: 0))
    }
}
