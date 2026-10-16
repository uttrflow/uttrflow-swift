// Tests that the committed accuracy baseline is one `make accuracy-gate` can compare a clean run with.
import Foundation
import Testing

@testable import UttrflowEval

@Suite("Committed accuracy baseline")
struct CommittedAccuracyBaselineTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func baseline() throws -> AccuracyBaseline {
        try AccuracyBaseline.read(from: root.appending(path: "Scripts/accuracy_baseline.json"))
    }

    @Test("records the recogniser it was measured with, or the gate has no verdict for any run")
    func recordsTheRecogniser() throws {
        let recogniser = try #require(try Self.baseline().recogniser)
        #expect(!recogniser.isEmpty)
    }

    @Test("holds every passage the gate synthesises, so no slice is measured against nothing")
    func coversEverySynthesisedPassage() throws {
        let english = TranscriptionCorpus.all.filter { $0.language == .english }
        let synthesised = english + TranscriptionCorpus.codeMixing
        let recorded = Set(try Self.baseline().entries.map(\.caseID))
        #expect(recorded == Set(synthesised.map(\.id)))
    }
}
