// The `rules-scorecard` command: which corpus cases the deterministic rules pass, for `make eval` to compare.
import ArgumentParser
private import Foundation
private import UttrflowAI
private import UttrflowEval

/// Writes, for every corpus case, its category and whether the rules alone pass it, as JSON with sorted keys.
struct RulesScorecard: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rules-scorecard",
        abstract: "Score the rules alone over the whole corpus and write each case's verdict as JSON."
    )

    @Option(name: .long, help: "Where to write the scorecard.")
    var output: String

    func run() async throws {
        let rules = RuleBasedTransformer()
        var cases: [String: [String: String]] = [:]
        for testCase in EvaluationCorpus.all {
            let written = try await rules.transform(testCase.transformationRequest()).text
            cases[testCase.id] = [
                "category": testCase.category.rawValue,
                "verdict": Scorer.score(written, against: testCase).passed ? "pass" : "fail",
            ]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(["cases": cases]).write(to: URL(fileURLWithPath: output))
        let passed = cases.values.filter { $0["verdict"] == "pass" }.count
        print("rules scorecard: \(passed) of \(cases.count) cases pass; written to \(output)")
    }
}
