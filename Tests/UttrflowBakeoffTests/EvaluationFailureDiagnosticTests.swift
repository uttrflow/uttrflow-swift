import Testing
import UttrflowCore
import UttrflowEval

@testable import uttrflow_bakeoff

struct EvaluationFailureDiagnosticTests {
    @Test(
        "diagnostics contain only the case identifier and fixed category",
        arguments: ModelFailureClass.allCases)
    func closedCategories(category: ModelFailureClass) {
        let testCase = EvaluationCase(
            id: "synthetic-case", category: .everyday,
            spoken: "Synthetic input excluded from diagnostics.", expected: "Synthetic reference.")
        #expect(
            EvaluationFailureDiagnostic.line(for: testCase, category: category)
                == "\n  ! synthetic-case: \(category.rawValue)\n")
    }
}
