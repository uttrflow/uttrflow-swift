import Foundation
import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// How many of the corpus cases that ask for a code symbol get it under the rules, per destination that writes them.
@Suite("Notation recall")
struct NotationRecallTests {
    /// The destinations whose notation the symbol rows write.
    static let destinations: [Destination] = [.codeEditor, .terminal]

    /// The fewest of each destination's notation cases the rules must write exactly, as measured when the evidence rule landed.
    static let floors: [Destination: Int] = [.codeEditor: 3, .terminal: 1]

    /// The cases outside the abstention set whose expected text holds a symbol only a code-symbol row writes.
    static func notationCases(at destination: Destination) -> [EvaluationCase] {
        let abstaining = Set(EvaluationCorpus.abstention.map(\.id))
        let marks = Set(SpokenCommands.codeSymbols.map(\.text)).filter { $0.count > 1 || "=|>{}_*".contains($0) }
        return EvaluationCorpus.all.filter { testCase in
            testCase.destination == destination && !abstaining.contains(testCase.id)
                && marks.contains { testCase.expected.contains($0) && !testCase.spoken.contains($0) }
        }
    }

    @Test("writes at least the floor of each destination's notation cases", arguments: destinations)
    func recallMeetsFloor(destination: Destination) async throws {
        let cases = Self.notationCases(at: destination)
        var written: [String] = []
        var missed: [String] = []
        for testCase in cases {
            let output = try await RuleBasedTransformer().transform(testCase.transformationRequest()).text
            if output == testCase.expected { written.append(testCase.id) } else { missed.append(testCase.id) }
        }
        print("notation recall \(destination): \(written.count)/\(cases.count) missed \(missed.sorted())")
        #expect(written.count >= Self.floors[destination] ?? 0)
    }
}
