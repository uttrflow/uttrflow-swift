// The rules' per-adapter score over the corpus, held to a committed baseline.
import Foundation
import Testing
import UttrflowAI
import UttrflowCore
import UttrflowTestSupport

@testable import UttrflowEval

/// Fails a change that lowers an adapter's exact-match count or adds a word or a broken shape to its cases.
@Suite("Per-adapter baseline for the rules")
struct AdapterBaselineTests {
    private static let baselineURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Golden").appendingPathComponent("adapters.json")

    /// What the rules alone score on every case that names an adapter, with a fixed date so the file is stable.
    private static func measured() async throws -> AdapterReport {
        let named = EvaluationCorpus.all.filter { $0.adapter != nil }
        var scores: [CaseScore] = []
        for testCase in named {
            let result = try await RuleBasedTransformer().transform(testCase.transformationRequest())
            scores.append(Scorer.score(result.text, against: testCase))
        }
        return AdapterReport(
            label: "rules", recordedAt: Date(timeIntervalSince1970: 0), cases: named, scores: scores)
    }

    @Test("a notation set's cases belong to its adapter, at least five per family")
    func families() {
        let counts = Dictionary(grouping: EvaluationCorpus.all.compactMap(\.adapter), by: \.rawValue)
            .mapValues(\.count)
        for family in ["markup", "source"] {
            #expect((counts[family] ?? 0) >= 5, "\(family)")
        }
    }

    @Test("a set name gives its adapter only when it ends in Notation")
    func setNames() {
        #expect(CorpusFile.adapter(ofSet: "markupNotation") == "markup")
        #expect(CorpusFile.adapter(ofSet: "Notation") == nil)
        #expect(CorpusFile.adapter(ofSet: "hostileSelectedText") == nil)
    }

    @Test("no adapter scores worse than the committed baseline")
    func holdsBaseline() async throws {
        let report = try await Self.measured()
        let update = ProcessInfo.processInfo.environment[GoldenFile.updateVariable] == "1"
        if update, ProcessInfo.processInfo.environment["CI"] == nil {
            try report.write(to: Self.baselineURL)
            return
        }
        let baseline = try AdapterReport.read(from: Self.baselineURL)
        switch report.worsened(against: baseline) {
        case .success(let worse):
            #expect(
                worse.isEmpty,
                "\(worse.joined(separator: ", ")) scored worse than the baseline:\n\(report.table)")
        case .failure(let incomparable):
            Issue.record(
                "\(incomparable.reason); rerun with \(GoldenFile.updateVariable)=1 if the cases changed")
        }
    }
}
