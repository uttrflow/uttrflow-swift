// The developer harness's root command.
import ArgumentParser
private import Foundation

/// Developer harness, one command per stage, so each ends in something a person can run and judge.
@main
struct UttrflowDev: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uttrflow-dev",
        abstract: "Exercise Uttrflow end to end, one phase at a time.",
        subcommands: [
            Doctor.self, Record.self, Models.self, Transcribe.self, Dictate.self, Clean.self, Explain.self,
            Insert.self,
            Context.self, SimulateField.self, Seams.self,
            SignIn.self, Probe.self, Machine.self, Bench.self, Burst.self, Latency.self, Launch.self,
        ]
    )
}
