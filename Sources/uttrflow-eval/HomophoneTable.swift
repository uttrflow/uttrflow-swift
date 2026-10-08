// The `homophone-table` command: AC.21's class-by-class error table over the generated homophone cases.
import ArgumentParser
private import UttrflowAI
private import UttrflowCore
private import UttrflowDictionary
private import UttrflowEval

/// Prints, per homophone class, the share of generated cases left wrong as heard and after the rules.
struct HomophoneTable: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "homophone-table",
        abstract: "Print the class-by-class homophone error table over the generated cases."
    )

    func run() throws {
        let stages = [
            HomophoneStage("raw") { $0 },
            HomophoneStage("rules") { CleaningPipeline.standard.run(Draft(text: $0)).text },
        ]
        let cases = HomophoneCaseSet.cases(
            classes: HomophoneCarriers.all.compactMap { Homophones.group(containing: $0.spelling) })
        let rows = HomophoneClassTable.rows(
            cases: cases, classOf: { Homophones.group(containing: $0) }, stages: stages)
        print(HomophoneClassTable.markdown(rows, stages: stages))
    }
}
