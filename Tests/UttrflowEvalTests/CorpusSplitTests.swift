// Tests which clean-up cases are held out, and that no prompt copies one.
import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

@Suite("Corpus split")
struct CorpusSplitTests {
    /// Every sentence and rule a model is shown, which is what a held-out case must never appear in.
    private static var promptFragments: [String] {
        let builder = PromptBuilder.standard
        return [builder.contract] + builder.blocks.values.map(\.rules) + builder.allWorkedExamples
    }

    @Test("the split is a pure function of the id, so it survives a new process")
    func splitIsStable() {
        #expect(CorpusSplit.digest("") == 0xcbf2_9ce4_8422_2325)
        #expect(CorpusSplit.digest("a") == 0xaf63_dc4c_8601_ec8c)
        for testCase in EvaluationCorpus.all {
            #expect(testCase.split == CorpusSplit(caseID: testCase.id))
        }
    }

    @Test("about one case in five is held out within every category and language of ten or more")
    func heldOutShareIsStratified() {
        let strata =
            EvaluationCase.Category.allCases.map { category in
                (category.rawValue, EvaluationCorpus.cases(in: category))
            }
            + Set(EvaluationCorpus.all.map(\.language)).map { language in
                (language.value, EvaluationCorpus.cases(for: language))
            }
        for (name, cases) in strata where cases.count >= 10 {
            let share = Double(cases.count(where: { $0.split == .heldout })) / Double(cases.count)
            #expect((0.1...0.3).contains(share), "\(name) holds out \(Int(share * 100))% of \(cases.count)")
        }
    }

    @Test("no prompt rule or worked example copies a held-out case")
    func promptCopiesNoHeldOutCase() {
        let leaks = CorpusSplit.leaks(of: EvaluationCorpus.all, into: Self.promptFragments)
        #expect(leaks.isEmpty, "held-out cases copied into the prompt: \(leaks)")
    }

    @Test("a held-out case copied into a prompt fragment is caught, and a development one is not")
    func copyingIsCaught() throws {
        let heldOut = try #require(
            EvaluationCorpus.all.first { $0.split == .heldout && $0.expected.count >= 12 })
        let development = try #require(
            EvaluationCorpus.all.first { $0.split == .development && $0.expected.count >= 12 })
        let fragments =
            Self.promptFragments + ["Spoken: x\nResult: \(heldOut.expected)", development.expected]
        let leaks = CorpusSplit.leaks(of: [heldOut, development], into: fragments)
        #expect(leaks.count == 1)
        #expect(leaks.first?.hasPrefix(heldOut.id + ":") == true)
    }

    @Test("a case written without an origin is authored and names no issue")
    func everyCaseHasAnOrigin() {
        let unlabelled = EvaluationCase(id: "x", category: .everyday, spoken: "a", expected: "A.")
        #expect(unlabelled.origin == .authored)
        #expect(unlabelled.addedFor == nil)
    }
}
