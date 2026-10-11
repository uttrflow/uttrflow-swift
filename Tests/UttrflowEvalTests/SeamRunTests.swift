// Tests the per-clip seam record a long-form run keeps and compares with its baseline.
import Foundation
import Testing
import UttrflowEval

@Suite("SeamRun")
struct SeamRunTests {
    private static let midClauseCut = SeamScore(
        whole: "We can ship it without any delay.", pieces: ["We can ship it without any.", "Delay."])
    private static let cleanCut = SeamScore(
        whole: "We can ship it today.", pieces: ["We can ship it", "today."])

    @Test func theTotalSumsEveryClip() {
        var run = SeamRun()
        run.record(Self.midClauseCut, for: "a")
        run.record(Self.midClauseCut, for: "b")
        run.record(Self.cleanCut, for: "c")
        #expect(run.total.strayStops == 2)
        #expect(run.total.wrongCapitals == 2)
        #expect(run.total.total == 4)
    }

    @Test func aClipThatGainedAnArtefactIsNamedWithItsKind() {
        var baseline = SeamRun()
        baseline.record(Self.cleanCut, for: "status")
        var run = SeamRun()
        run.record(Self.midClauseCut, for: "status")
        #expect(run.rises(over: baseline) == ["status: stray stops 0 -> 1", "status: wrong capitals 0 -> 1"])
    }

    @Test func aClipTheBaselineLacksIsHeldAtZero() {
        var run = SeamRun()
        run.record(Self.midClauseCut, for: "new")
        run.record(Self.cleanCut, for: "clean")
        #expect(run.rises(over: SeamRun()).count == 2)
        #expect(run.rises(over: SeamRun()).allSatisfy { $0.hasPrefix("new: ") })
    }

    @Test func fewerArtefactsThanTheBaselineIsNoRise() {
        var baseline = SeamRun()
        baseline.record(Self.midClauseCut, for: "status")
        var run = SeamRun()
        run.record(Self.cleanCut, for: "status")
        #expect(run.rises(over: baseline).isEmpty)
    }

    @Test func aWrittenRunReadsBackUnchanged() throws {
        var run = SeamRun()
        run.record(Self.midClauseCut, for: "status")
        let url = FileManager.default.temporaryDirectory.appending(path: "seam-run-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try run.write(to: url)
        #expect(try SeamRun.read(from: url) == run)
    }

    @Test func aMissingFileIsAReadError() {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "seam-run-absent-\(UUID().uuidString).json")
        #expect(throws: EvaluationStoreError.self) { try SeamRun.read(from: url) }
    }

    @Test func aRunThatCannotBeWrittenIsAWriteError() {
        let url = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/seam-run.json")
        #expect(throws: EvaluationStoreError.self) { try SeamRun().write(to: url) }
    }
}
