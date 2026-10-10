import Foundation
import Testing
import UttrflowAI
import UttrflowCore
import UttrflowTestSupport

@testable import UttrflowEval

/// The rules path and the model path format every tagged case the same way, or the gap is on record.
@Suite("Formatting parity between the rules and the model path")
struct FormattingParityTests {
    /// The generated page, three folders above this test file.
    static let page = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Docs/formatting-parity.md")

    /// Cases in a class the rules own or share that only the model path passes; a baseline that only shrinks.
    static let knownGaps: Set<String> = [
        // A colon inside a token is spaced as prose: "8000: 8000", "node: 20".
        "probe-docker-run-flags", "probe-dockerfile-from",
        // A spoken code-comment marker and mention are written as words.
        "probe-todo-comment",
        // A long stretch with no pause is one sentence.
        "probe-apology-message",
        // Counts in prose stay words where the destination writes numerals.
        "fmt-list-count-not-list",
    ]

    /// Cases tagged with a class only the model writes, which the rules are not asked to match.
    static let modelOwned = Set(
        tagged.filter { $0.classes.contains { $0.ownership.owner == .model } }.map(\.id))

    /// Both paths' outputs for every tagged case, computed once and in parallel.
    static let outputs = Task { () -> [String: FormattingParity.Outputs] in
        await withTaskGroup(of: (String, FormattingParity.Outputs).self) { group in
            for testCase in tagged {
                group.addTask { (testCase.id, await FormattingParityTests.outputs(for: testCase)) }
            }
            var outputs: [String: FormattingParity.Outputs] = [:]
            for await (id, output) in group { outputs[id] = output }
            return outputs
        }
    }

    static let tagged = (EvaluationCorpus.all + EvaluationCorpus.abstention).filter { !$0.classes.isEmpty }

    /// One case through the rules, then through the shipped model path with a model that answers the expected text.
    static func outputs(for testCase: EvaluationCase) async -> FormattingParity.Outputs {
        let request = testCase.transformationRequest()
        let rules = (try? await RuleBasedTransformer().transform(request).text) ?? ""
        let model = ExpectedAnswerModel(answer: testCase.expectedExact ?? testCase.expected)
        let finished = try? await GenerativeTextTransformer(kind: .foundationModels, model: model)
            .transform(request).text
        return FormattingParity.Outputs(rules: rules, model: finished)
    }

    static func parity() async -> FormattingParity {
        FormattingParity(cases: tagged, outputs: await outputs.value)
    }

    @Test(
        "lets only the model path pass a case in a rules-owned or shared class only where the gap is recorded"
    )
    func onlyModelGapsAreRecorded() async {
        for row in await Self.parity().rows where row.formattingClass.ownership.owner != .model {
            let unrecorded = Set(row.onlyModel).subtracting(Self.knownGaps).subtracting(Self.modelOwned)
            #expect(
                unrecorded.isEmpty,
                "\(row.formattingClass.rawValue): only the model path passes \(unrecorded.sorted())")
        }
    }

    @Test("drops a recorded gap once the rules pass it, so the baseline only shrinks")
    func knownGapsStillFail() async {
        let open = Set(await Self.parity().rows.flatMap(\.onlyModel))
        #expect(
            Self.knownGaps.subtracting(open).isEmpty,
            "now closed: \(Self.knownGaps.subtracting(open).sorted())")
    }

    @Test("never lets the finishing passes break a case the rules pass on their own")
    func modelPathKeepsWhatTheRulesGetRight() async {
        for row in await Self.parity().rows {
            #expect(row.onlyRules.isEmpty, "\(row.formattingClass.rawValue): \(row.onlyRules)")
        }
    }

    @Test("splits a class's cases by which path passes, a refused answer falling back to the rules")
    func splitsByPath() {
        let cases = EvaluationCorpus.formatting.filter { $0.classes.contains(.ellipses) }.prefix(4)
        let ids = cases.map(\.id)
        let right = cases.map { $0.expectedExact ?? $0.expected }
        let outputs: [String: FormattingParity.Outputs] = [
            ids[0]: .init(rules: right[0], model: right[0]),
            ids[1]: .init(rules: "", model: right[1]),
            ids[2]: .init(rules: right[2], model: ""),
            ids[3]: .init(rules: right[3], model: nil),
        ]
        let row = FormattingParity(cases: Array(cases), outputs: outputs).rows.first {
            $0.formattingClass == .ellipses
        }
        #expect(row?.both == 2)
        #expect(row?.onlyModel == [ids[1]])
        #expect(row?.onlyRules == [ids[2]])
        #expect(row?.refused == [ids[3]])
    }

    @Test("matches Docs/formatting-parity.md, which is generated from both paths' outputs")
    func pageMatchesOutputs() async throws {
        let generated = await Self.parity().markdown
        let environment = ProcessInfo.processInfo.environment
        if environment[GoldenFile.updateVariable] == "1", environment["CI"] == nil {
            try generated.write(to: Self.page, atomically: true, encoding: .utf8)
        }
        let recorded = try String(contentsOf: Self.page, encoding: .utf8)
        #expect(recorded == generated, "rerun with \(GoldenFile.updateVariable)=1 to regenerate the page")
    }
}

/// A stand-in model that answers with the case's expected text, so only the passes around it can lose a case.
private struct ExpectedAnswerModel: CleanupModel {
    let answer: String

    func availability(for language: LanguageCode?) async -> TransformerAvailability { .available }

    func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        answer
    }
}
