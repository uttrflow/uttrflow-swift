import ArgumentParser

/// The evaluation harness: records a corpus once, then measures transcription against it.
@main
struct UttrflowEvalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uttrflow-eval",
        abstract: "Measure how well Uttrflow hears and how fast it answers.",
        subcommands: [RecordCorpus.self, PullCorpus.self, TranscribeCorpus.self]
    )
}
