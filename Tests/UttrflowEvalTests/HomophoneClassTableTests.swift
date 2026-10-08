// Tests that AC.21's class table is read from the generated cases and counts each stage's errors.
import Testing
import UttrflowAI
import UttrflowCore
@testable import UttrflowEval

@testable import UttrflowDictionary

@Suite("HomophoneClassTable")
struct HomophoneClassTableTests {
    static let cases = HomophoneCaseSet.cases(classes: Homophones.groups)
    static let identity = HomophoneStage("raw") { $0 }

    @Test func everyClassWithCarriersHasOneRowAndEveryCaseIsCounted() {
        let rows = HomophoneClassTable.rows(
            cases: Self.cases, classOf: { Homophones.group(containing: $0) }, stages: [Self.identity])
        #expect(rows.count == Homophones.groups.count)
        #expect(rows.map(\.cases).reduce(0, +) == Self.cases.count)
        #expect(Set(rows.map(\.members)).count == rows.count)
    }

    @Test func rawLeavesEveryGeneratedCaseWrong() {
        let rows = HomophoneClassTable.rows(
            cases: Self.cases, classOf: { Homophones.group(containing: $0) }, stages: [Self.identity])
        #expect(rows.allSatisfy { $0.errors == [$0.cases] })
    }

    @Test func aStageThatWritesTheMeantSentenceLeavesNoError() {
        let byInput = Dictionary(
            Self.cases.map { ($0.input, $0.expected) }, uniquingKeysWith: { first, _ in first })
        let oracle = HomophoneStage("oracle") { byInput[$0] ?? $0 }
        let rows = HomophoneClassTable.rows(
            cases: Self.cases, classOf: { Homophones.group(containing: $0) }, stages: [oracle])
        #expect(byInput.count == Self.cases.count)
        #expect(rows.allSatisfy { $0.errors == [0] })
    }

    @Test func comparisonKeepsApostrophesAndDropsCaseAndStops() {
        let case1 = HomophoneCase(
            input: "its late", expected: "it's late", meant: "it's", heard: "its", decider: .role)
        let capitalised = HomophoneStage("rules") { _ in "It\u{2019}s late." }
        let rows = HomophoneClassTable.rows(
            cases: [case1], classOf: { _ in nil }, stages: [Self.identity, capitalised])
        #expect(rows == [HomophoneClassRow(members: "it's", cases: 1, errors: [1, 0])])
    }

    @Test func markdownPrintsOneLinePerClassWithRoundedRates() {
        let rows = [HomophoneClassRow(members: "a/b", cases: 3, errors: [3, 1])]
        let stages = [Self.identity, HomophoneStage("rules") { $0 }]
        #expect(
            HomophoneClassTable.markdown(rows, stages: stages)
                == "| Class | Cases | raw | rules |\n|---|---|---|---|\n| a/b | 3 | 100% | 33% |")
        #expect(
            HomophoneClassTable.markdown(
                [HomophoneClassRow(members: "x", cases: 0, errors: [0])], stages: [Self.identity]
            ).hasSuffix("| x | 0 | - |"))
    }

    @Test func theStandardRulesStageRuns() {
        let rules = HomophoneStage("rules") { CleaningPipeline.standard.run(Draft(text: $0)).text }
        let rows = HomophoneClassTable.rows(
            cases: Self.cases, classOf: { Homophones.group(containing: $0) }, stages: [Self.identity, rules])
        #expect(rows.allSatisfy { $0.errors[1] <= $0.cases })
    }
}
