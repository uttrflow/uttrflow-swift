import ArgumentParser
import Foundation
import Testing
import UttrflowCore
@testable import uttrflow_bakeoff
@testable import UttrflowEval

struct ReloadLeaksTests {
    @Test("bake-off comparison catches a lost pass and rising lost words")
    func bakeoffComparisonFindsRegressions() {
        let baseline = measurement(cases: [
            caseResult("pass-to-fail", passed: true),
            caseResult("lost-words", passed: false, lost: ["one"]),
            caseResult("missing", passed: true),
        ])
        let current = measurement(cases: [
            caseResult("pass-to-fail", passed: false),
            caseResult("lost-words", passed: false, lost: ["one", "two"]),
        ])

        let comparison = RegressionComparison.compare(current, against: baseline)
        #expect(
            comparison?.regressions == [
                "lost-words: lost words increased from 1 to 2",
                "pass-to-fail: previously passing case now fails",
            ])
        #expect(comparison?.removed == ["missing"])
    }

    @Test("bake-off comparison fails a category whose marks or case fall while every case still passes")
    func bakeoffComparisonFindsMarkAndCaseDrops() throws {
        let baseline = measurement(cases: [caseResult("a", passed: true, mark: 1, casing: 1)])
        let current = measurement(cases: [caseResult("a", passed: true, mark: 0.5, casing: 1)])
        let comparison = try #require(RegressionComparison.compare(current, against: baseline))
        #expect(comparison.regressions == ["category everyday: mark accuracy fell from 100.0% to 50.0%"])
        #expect(RegressionComparison.compare(baseline, against: current)?.regressions == [])
    }

    @Test("bake-off comparison judges only unchanged cases and names added, removed and changed ones")
    func bakeoffComparisonSeparatesCorpusChanges() throws {
        let baseline = measurement(
            cases: [
                caseResult("same", passed: true, identity: "a"),
                caseResult("edited", passed: true, identity: "b"),
                caseResult("dropped", passed: true, identity: "c"),
            ], corpus: "old")
        let current = measurement(
            cases: [
                caseResult("same", passed: true, identity: "a"),
                caseResult("edited", passed: false, identity: "b2"),
                caseResult("new", passed: false, identity: "d"),
            ], corpus: "new")

        let comparison = try #require(RegressionComparison.compare(current, against: baseline))
        #expect(comparison.regressions.isEmpty)
        #expect(comparison.added == ["new"])
        #expect(comparison.removed == ["dropped"])
        #expect(comparison.changed == ["edited"])
        #expect(comparison.corpusChanged)
        #expect(comparison.corpusReport.first?.hasPrefix("Corpus changed") == true)
    }

    @Test("an unchanged corpus reports nothing about the corpus")
    func bakeoffComparisonQuietOnSameCorpus() throws {
        let same = measurement(cases: [caseResult("same", passed: true, identity: "a")], corpus: "x")
        let comparison = try #require(RegressionComparison.compare(same, against: same))
        #expect(comparison.corpusReport.isEmpty)
    }

    @Test("a case's identity moves with what it is scored on and not with its labels")
    func caseIdentityIgnoresLabels() {
        let base = EvaluationCase(id: "x", category: .everyday, spoken: "hi there", expected: "Hi there.")
        let relabelled = EvaluationCase(
            id: "x", category: .everyday, spoken: "hi there", expected: "Hi there.", origin: .synthetic,
            addedFor: 1)
        let edited = EvaluationCase(id: "x", category: .everyday, spoken: "hi there", expected: "Hi, there.")
        let otherContext = EvaluationCase(
            id: "x", category: .everyday, spoken: "hi there", expected: "Hi there.",
            context: AppContext(applicationName: "Notes"))
        #expect(base.identity == relabelled.identity)
        #expect(base.identity != edited.identity)
        #expect(base.identity != otherContext.identity)
        #expect(
            EvaluationCase.corpusIdentity(of: [base]) != EvaluationCase.corpusIdentity(of: [edited]))
    }

    @Test("bake-off comparison ignores a different candidate")
    func bakeoffComparisonRequiresMatchingCandidate() {
        let rules = measurement(cases: [])
        let other = Measurement(
            description: CandidateDescription(
                name: "other", version: "—", parameters: "—", quantisation: "—", size: "0"),
            report: EvaluationReport(label: "other", scores: [], durations: []))
        #expect(RegressionComparison.compare(rules, against: other) == nil)
    }

    private func measurement(
        cases: [StoredReport.CaseResult],
        corpus: String? = nil
    ) -> uttrflow_bakeoff.Measurement {
        let scores = cases.map {
            CaseScore(
                caseID: $0.caseID, similarity: $0.passed ? 1 : 0,
                keptEverythingRequired: $0.lost.isEmpty, lost: $0.lost, isExact: $0.passed)
        }
        var result = Measurement(
            description: .rules, report: EvaluationReport(label: "rules", scores: scores, durations: []))
        result.report.cases = cases
        result.report.corpusIdentity = corpus
        return result
    }

    private func caseResult(
        _ id: String,
        passed: Bool,
        lost: [String] = [],
        identity: String? = nil,
        mark: Double? = nil,
        casing: Double? = nil
    ) -> StoredReport.CaseResult {
        StoredReport.CaseResult(
            caseID: id, category: "everyday", destination: nil, similarity: passed ? 1 : 0,
            markAccuracy: mark, caseAccuracy: casing, lost: lost, invented: [], brokeShape: [],
            passed: passed, declined: false, identity: identity)
    }

    @Test("scorecard and fixture report use judged shown rows for category precision")
    func scorecardMatchesFixtureReportPrecision() throws {
        let results = [
            FixtureResult(
                name: "chat/right", category: "chat", typed: "hello", hit: true, judged: true,
                conforms: true, elapsedMs: 10, first: "hello", drawn: ["hello"], raw: nil, invented: false),
            FixtureResult(
                name: "chat/wrong", category: "chat", typed: "world", hit: false, judged: true,
                conforms: true, elapsedMs: 12, first: "wrong", drawn: ["wrong"], raw: nil, invented: false),
            FixtureResult(
                name: "chat/unjudged", category: "chat", typed: "continuation", hit: true, judged: false,
                conforms: true, elapsedMs: 14, first: "continuation", drawn: ["continuation"], raw: nil,
                invented: false),
        ]
        let report = FixtureReport(results: results)
        let category = try #require(report.summary.categories.first)
        #expect(category.shown == 2)
        #expect(category.right == 1)

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try report.write(to: directory.appending(path: "fixture.json").path)
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Scripts/predict_scorecard.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, directory.appending(path: "fixture.json").path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(text.contains("precision 50.00 % (1/2 judged shown, 1 wrong"))
        #expect(
            text.contains(
                "chat       n=   3 hit  67 %  register 100 %  p50   12  precision   50.0%  wrong   1")
        )
    }

    @Test("no-candidate rows are not shown whether silence was expected or not")
    func noCandidateRowsAreNotShown() throws {
        let results = [
            FixtureResult(
                name: "search/silence", category: "search", typed: "inv", hit: true, judged: true,
                conforms: true, elapsedMs: 10, first: "invoice", drawn: [], raw: nil, invented: false),
            FixtureResult(
                name: "chat/miss", category: "chat", typed: "hello", hit: false, judged: true,
                conforms: false, elapsedMs: 12, first: "world", drawn: [], raw: nil, invented: false),
        ]
        let report = FixtureReport(results: results)
        let search = try #require(report.summary.categories.first { $0.name == "search" })
        let chat = try #require(report.summary.categories.first { $0.name == "chat" })
        #expect(search.shown == 0)
        #expect(search.right == 0)
        #expect(chat.shown == 0)
        #expect(chat.right == 0)
    }

    @Test("stored bake-off results retain surface metrics and old files still decode")
    func storedSurfaceMetricsRemainBackwardCompatible() throws {
        let legacy = Data(
            #"{"passRate":0,"meanSimilarity":0,"medianSeconds":0,"slowestSeconds":0,"declinedCount":0,"lostWordCount":0,"cases":[{"caseID":"legacy","category":"everyday","similarity":1,"lost":[],"passed":true,"declined":false}]}"#
                .utf8)
        let old = try JSONDecoder().decode(StoredReport.self, from: legacy)
        #expect(old.meanMarkAccuracy == nil)
        #expect(old.meanCaseAccuracy == nil)
        #expect(old.cases.first?.markAccuracy == nil)
        #expect(old.cases.first?.caseAccuracy == nil)

        let score = CaseScore(
            caseID: "surface", similarity: 1, markAccuracy: 0.5, caseAccuracy: 0.75,
            keptEverythingRequired: true, lost: [], isExact: false)
        let report = EvaluationReport(label: "surface", scores: [score], durations: [])
        let measurement = Measurement(description: .rules, report: report)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        try ResultStore(directory: directory).save(measurement)
        let stored = try #require(ResultStore(directory: directory).all().first?.report)
        #expect(stored.meanMarkAccuracy == 0.5)
        #expect(stored.meanCaseAccuracy == 0.75)
        #expect(stored.cases.first?.markAccuracy == 0.5)
        #expect(stored.cases.first?.caseAccuracy == 0.75)
    }

    @Test("checkpoints must be positive before the median is calculated")
    func checkpointsMustBePositive() throws {
        #expect(try ReloadLeaks.parseCheckpoints("1,5,20") == [1, 5, 20])
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("0")
        }
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("1,0,2")
        }
    }

    @Test("checkpoints must remain ascending whole numbers")
    func checkpointsMustBeAscendingWholeNumbers() {
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("5,1")
        }
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("1,x,5")
        }
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("1,,5")
        }
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints(",1,5")
        }
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("1,5,")
        }
    }
}
