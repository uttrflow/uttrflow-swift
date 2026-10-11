// Tests that `--case` narrows a bake-off run to the one case it names, and refuses what it cannot run.
import ArgumentParser
import Testing
@testable import uttrflow_bakeoff
@testable import UttrflowEval

struct CaseSelectionTests {
    @Test("with no --case the whole corpus is scored")
    func wholeCorpusByDefault() throws {
        #expect(try Bakeoff.parse([]).scored == EvaluationCorpus.all)
    }

    @Test("--case scores the one case it names")
    func oneCase() throws {
        let named = try #require(EvaluationCorpus.all.last)
        #expect(try Bakeoff.parse(["--case", named.id]).scored == [named])
    }

    @Test("--case refuses an id the scored corpus does not hold")
    func unknownID() {
        #expect(throws: (any Error).self) { try Bakeoff.parse(["--case", "no-such-case"]) }
    }

    @Test("--case refuses a flag that reads or compares stored whole runs")
    func storedRunFlags() throws {
        let id = try #require(EvaluationCorpus.all.first?.id)
        for flags in [["--summarise"], ["--sample"], ["--against", "a.json"], ["--ledger", "l.md"]] {
            #expect(throws: (any Error).self, "\(flags)") { try Bakeoff.parse(["--case", id] + flags) }
        }
    }
}
