// Tests that each bake-off result names what produced it and that runs are kept apart.
import Foundation
import Testing
import UttrflowCore
@testable import uttrflow_bakeoff
@testable import UttrflowEval

struct RunHeaderTests {
    private func header(runID: String, corpus: String = "c1", system: String = "25A1") -> RunHeader {
        RunHeader(
            runID: runID, date: Date(timeIntervalSince1970: 0), promptVersion: "p1", corpusIdentity: corpus,
            caseCount: 3, sourceRevision: "abc", systemBuild: system, chip: "Chip", memoryBytes: 1 << 34,
            contextWithheld: false)
    }

    private func measurement(_ header: RunHeader?) -> uttrflow_bakeoff.Measurement {
        Measurement(
            description: .rules, report: EvaluationReport(label: "rules", scores: [], durations: []),
            header: header)
    }

    private func temporaryStore() -> ResultStore {
        ResultStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    @Test("the current header fills every field")
    func currentHeaderIsComplete() {
        let current = RunHeader.current(contextWithheld: true)
        #expect(!current.runID.isEmpty && !current.promptVersion.isEmpty && !current.corpusIdentity.isEmpty)
        #expect(!current.sourceRevision.isEmpty && !current.systemBuild.isEmpty && !current.chip.isEmpty)
        #expect(current.caseCount == EvaluationCorpus.all.count && current.contextWithheld)
    }

    @Test("two runs of one engine are two files, and the latest is the one reported")
    func runsAreAppended() throws {
        let store = temporaryStore()
        try store.save(measurement(header(runID: "20260101T000000Z")))
        try store.save(measurement(header(runID: "20260102T000000Z")))
        let history = try store.history()
        #expect(history.count == 2)
        #expect(history.allSatisfy { $0.header?.promptVersion == "p1" && $0.header?.systemBuild == "25A1" })
        #expect(try store.all().map { $0.header?.runID } == ["20260102T000000Z"])
    }

    @Test("a comparison across corpus versions is refused with the reason")
    func differentCorpusIsRefused() throws {
        let baseline = measurement(header(runID: "a", corpus: "old"))
        let newer = header(runID: "b", corpus: "new")
        #expect(throws: (any Error).self) {
            try Bakeoff.refuseUnintendedDifferences(newer, baseline: baseline, allowing: [])
        }
        let reasons = newer.differences(from: try #require(baseline.header), allowing: [])
        #expect(reasons == ["corpus differs: baseline old, now new"])
        #expect(throws: Never.self) {
            try Bakeoff.refuseUnintendedDifferences(newer, baseline: baseline, allowing: [.corpus])
        }
    }

    @Test("the header names the layers a run had on, and a comparison across them is refused")
    func layersAreNamed() throws {
        let without = try #require(QualityLayers.ablation(only: nil, without: "formatting"))
        let current = RunHeader.current(contextWithheld: false, layers: without)
        #expect(current.summary.hasSuffix("layers " + without.names.joined(separator: ",")))
        #expect(!current.layerNames.contains("formatting"))

        let stored = header(runID: "a")
        #expect(stored.layerNames == QualityLayers().names.joined(separator: ","))
        var ablated = header(runID: "b")
        ablated.layers = without.names
        #expect(ablated.differences(from: stored, allowing: []).first?.hasPrefix("layers differs") == true)
        #expect(ablated.differences(from: stored, allowing: [.layers]).isEmpty)
    }

    @Test("the ledger lists the latest run per prompt version and macOS build")
    func ledgerKeepsLatest() {
        let ledger = ResultLedger.markdown(of: [
            measurement(header(runID: "1", system: "25A1")), measurement(header(runID: "2", system: "25A1")),
            measurement(header(runID: "3", system: "25B2")),
        ])
        #expect(ledger.contains("| p1 | 25A1 | rules — | 0% | 2 |"))
        #expect(!ledger.contains("| 1 |"))
        #expect(ledger.contains("| p1 | 25B2 |"))
    }
}
