import ArgumentParser
import Foundation
import Testing
import UttrflowEval
import UttrflowPredict
@testable import uttrflow_bakeoff

@Suite("The complete bake-off saves reports and guards regressions", .bug(id: 5073))
struct CompleteRegressionTests {
    @Test("A precision regression fails after saving its report")
    func precisionRegressionSavesReport() throws {
        let baseline = report([
            result("first", hit: true, drawn: ["right"]), result("second", hit: false, drawn: []),
        ])
        let current = report([
            result("first", hit: true, drawn: []), result("second", hit: false, drawn: ["wrong"]),
        ])

        let saved = try failureReport(current, baseline: baseline)
        #expect(saved.summary.shown == 1)
        let noPrecision = report([
            result("first", hit: true, drawn: []), result("second", hit: false, drawn: []),
        ])
        let lowerHitRate = report([
            result("first", hit: false, drawn: []), result("second", hit: false, drawn: []),
        ])
        #expect(throws: ExitCode.self) {
            try Complete.requireNoRegression(lowerHitRate, against: noPrecision)
        }
    }

    @Test("An errored fixture report is saved before failure")
    func errorReportSavesBeforeFailure() throws {
        let failed = FixtureResult(
            name: "terminal/error", category: "terminal", typed: "git status", hit: false,
            judged: true, conforms: false, elapsedMs: 1, first: nil, drawn: [], raw: nil,
            invented: false, error: "generator failed")

        #expect(try failureReport(report([failed])).summary.errors == 1)
    }

    @Test("A small sample prints its uncertainty interval")
    func smallSampleRateIncludesWilsonInterval() {
        #expect(FixtureReport.interval(3, of: 4).contains("95% Wilson CI 30.06–95.44%"))
        #expect(
            FixtureReport.measuredCoverage(3, of: 4)
                == "75.00 % (3/4) [95% Wilson CI 30.06–95.44%]")
    }

    @Test("Changed fixture inputs invalidate a saved baseline")
    func fixtureInputsChangeIdentity() {
        let situation = GenerationSituation(application: "Terminal", document: "/Users/me/project")
        let original = Fixture(
            "terminal/same", situation, typed: "git c",
            expectation: CompletionExpectation(acceptable: ["ommit"], band: 1...40))
        let changedAnswer = Fixture(
            "terminal/same", situation, typed: "git c",
            expectation: CompletionExpectation(acceptable: ["heckout"], band: 1...40))
        rejects(changedAnswer, original)
    }

    @Test("A run judged against a baseline fails when it cannot measure")
    func unmeasuredBaselineRunFails() throws {
        #expect(throws: ExitCode.self) { try Complete.ensureMeasurementAllowed(report([])) }
        try Complete.ensureMeasurementAllowed(nil)
    }

    @Test("A symlinked JSON output cannot overwrite its baseline")
    func symlinkedJSONPathCannotOverwriteBaseline() throws {
        let baseline = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let alias = baseline.appendingPathExtension("link")
        defer {
            try? FileManager.default.removeItem(at: alias)
            try? FileManager.default.removeItem(at: baseline)
        }
        try Data().write(to: baseline)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: baseline)
        #expect(throws: ValidationError.self) {
            try Complete.validateOutputPaths(baseline: baseline.path, json: alias.path)
        }
    }

    private func report(_ results: [FixtureResult]) -> FixtureReport { .init(results: results) }

    private func result(_ name: String, hit: Bool, drawn: [String], identity: String? = nil) -> FixtureResult
    {
        FixtureResult(
            name: "terminal/\(name)", category: "terminal", typed: name, hit: hit,
            judged: true, conforms: hit, elapsedMs: 1, first: drawn.first, drawn: drawn,
            raw: nil, invented: false, fixtureIdentity: identity ?? "fingerprint-\(name)")
    }

    private func failureReport(
        _ report: FixtureReport, baseline: FixtureReport? = nil
    ) throws -> FixtureReport {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appending(path: "report.json").path
        #expect(throws: ExitCode.self) { try Complete.finish(report, writingTo: path, baseline: baseline) }
        return try FixtureReport.load(from: path)
    }

    private func rejects(_ fixture: Fixture, _ baselineFixture: Fixture) {
        #expect(throws: ValidationError.self) {
            try Complete.requireNoRegression(
                report([result("same", hit: true, drawn: ["git commit"], identity: fixture.identity)]),
                against: report([
                    result("same", hit: true, drawn: ["git commit"], identity: baselineFixture.identity)
                ]))
        }
    }
}
