import ArgumentParser
private import Foundation

/// Developer harness, one command per stage, so each ends in something a person can run and judge.
@main
struct UttrflowDev: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uttrflow-dev",
        abstract: "Exercise Uttrflow end to end, one phase at a time.",
        subcommands: [
            Doctor.self, Record.self, Models.self, Transcribe.self, Clean.self, Insert.self, Context.self,
            SignIn.self, Probe.self,
        ]
    )
}
