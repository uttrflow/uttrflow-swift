import Testing
import UttrflowCore
@testable import uttrflow_bakeoff
@testable import UttrflowEval

@Suite("Bake-off meaning guard false-refusal line")
struct GuardFalseRefusalReportTests {
    @Test("the report counts every case and names each refused one")
    func countsAndNamesRefusals() {
        let corpus = Array(EvaluationCorpus.all.prefix(40))
        let lines = Bakeoff.guardFalseRefusals(over: corpus).split(separator: "\n")
        #expect(lines.first?.hasSuffix("of \(corpus.count) expected texts") == true)
        #expect(lines.first?.contains("false refusals: \(lines.count - 1) of") == true)
    }
}
