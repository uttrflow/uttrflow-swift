import ArgumentParser
import UttrflowAI

/// Prints every rule line and worked example of the shipping prompt with the tokens it costs; no model loads.
struct PromptCost: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prompt-cost",
        abstract: "Print each prompt rule line and example with its estimated token cost."
    )

    func run() {
        print(PromptBuilder.standard.ablationCostTable())
    }
}
