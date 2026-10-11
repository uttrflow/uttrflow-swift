// The `autolearn-replay` command: scores the pair learner on synthetic edits and fails when a bound is missed.
import ArgumentParser
private import UttrflowEval

/// Replays true fixes and decoy edits from the repo corpus through the default learner and prints the report.
struct AutoLearnReplayProbe: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "autolearn-replay",
        abstract: "Score what the pair learner learns from synthetic edits before any of it ships on."
    )

    func run() throws {
        let scenario = AutoLearnReplay.scenario(from: EvaluationCorpus.all)
        let report = AutoLearnReplay.replay(scenario.edits, heldOut: scenario.heldOut)
        print("\(scenario.edits.count) edits; \(scenario.heldOut.count) held-out words")
        print(report.markdown)
        guard report.meetsBounds else { throw ExitCode.failure }
    }
}
