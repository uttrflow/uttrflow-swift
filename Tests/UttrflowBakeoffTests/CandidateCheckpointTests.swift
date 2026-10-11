import Foundation
import Testing
import UttrflowEval

@testable import uttrflow_bakeoff

struct CandidateCheckpointTests {
    private enum Interrupted: Error { case candidate }

    private var header: RunHeader {
        RunHeader(
            runID: "20260101T000000Z", date: Date(timeIntervalSince1970: 0), promptVersion: "synthetic",
            corpusIdentity: "synthetic", caseCount: 0, sourceRevision: "synthetic",
            systemBuild: "synthetic", chip: "synthetic", memoryBytes: 1, contextWithheld: false)
    }

    private func measurement(_ description: CandidateDescription = .rules) -> uttrflow_bakeoff.Measurement {
        Measurement(
            description: description, report: EvaluationReport(label: "synthetic", scores: [], durations: []))
    }

    private func temporaryStore() -> ResultStore {
        ResultStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    @Test("a later interrupted candidate leaves the completed baseline readable")
    func completedBaselineSurvivesInterruption() async throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        await #expect(throws: Interrupted.self) {
            try await Bakeoff.measureCandidates(
                baselines: [{ measurement() }, { throw Interrupted.candidate }], locals: { [] },
                header: header, storage: .fullRun(store, baselineURL: nil))
        }
        let saved = try store.history()
        #expect(saved.count == 1)
        #expect(saved.first?.description.fileName == CandidateDescription.rules.fileName)
        #expect(saved.first?.header?.runID == header.runID)
        #expect(saved.first?.header?.promptVersion == header.promptVersion)
    }

    @Test("local candidate selection happens after completed baselines reach disk")
    func completedBaselineSurvivesSelectionFailure() async throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        await #expect(throws: Interrupted.self) {
            try await Bakeoff.measureCandidates(
                baselines: [{ measurement() }],
                locals: {
                    #expect(try store.history().count == 1)
                    throw Interrupted.candidate
                }, header: header, storage: .fullRun(store, baselineURL: nil))
        }
        #expect(try store.history().count == 1)
    }

    @Test("all completed candidates retain one shared header and their measurement order")
    func candidatesShareTheRun() async throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let measured = try await Bakeoff.measureCandidates(
            baselines: [{ measurement() }], locals: { [{ measurement(.appleOnDevice) }] },
            header: header, storage: .fullRun(store, baselineURL: nil))
        #expect(
            measured.map { $0.description.fileName } == [
                CandidateDescription.rules.fileName, CandidateDescription.appleOnDevice.fileName,
            ])
        #expect(measured.allSatisfy { $0.header?.runID == header.runID })
        let saved = try store.history()
        #expect(saved.count == 2)
        #expect(
            saved.allSatisfy {
                $0.header?.runID == header.runID && $0.header?.promptVersion == header.promptVersion
            })
    }

    @Test("single-case measurements carry the header but create no stored report")
    func singleCaseIsNotStored() async throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let measured = try await Bakeoff.measureCandidates(
            baselines: [{ measurement() }], locals: { [] }, header: header,
            storage: .singleCase)
        #expect(measured.count == 1)
        #expect(measured.first?.header?.runID == header.runID)
        #expect(try store.history().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.directory.path))
    }

    @Test("a checkpoint refuses to overwrite its baseline bytes")
    func comparisonBaselineIsProtected() async throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var baseline = measurement()
        baseline.header = header
        try store.save(baseline)
        let url = store.fileURL(for: baseline).standardizedFileURL
        let bytes = try Data(contentsOf: url)
        await #expect(throws: (any Error).self) {
            try await Bakeoff.measureCandidates(
                baselines: [{ measurement() }], locals: { [] }, header: header,
                storage: .fullRun(store, baselineURL: url))
        }
        #expect(try Data(contentsOf: url) == bytes)
    }
}
