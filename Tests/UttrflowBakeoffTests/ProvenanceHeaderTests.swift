// Tests the bake-off header's count of cases by origin and split.
import Testing
@testable import uttrflow_bakeoff
@testable import UttrflowEval

struct ProvenanceHeaderTests {
    @Test("the header counts every origin and every split, zeros included")
    func countsOriginsAndSplits() {
        let cases = [
            EvaluationCase(id: "a", category: .everyday, spoken: "a", expected: "A."),
            EvaluationCase(id: "b", category: .everyday, spoken: "b", expected: "B.", origin: .synthetic),
        ]
        let held = cases.count(where: { $0.split == .heldout })
        #expect(
            Bakeoff.provenance(of: cases)
                == "origin: authored 1, reportRewrite 0, synthetic 1; split: development \(2 - held), heldout \(held)"
        )
    }
}
