import ArgumentParser

/// Phase 8's harness.
///
/// Separate from `uttrflow-dev` because the transcription measurement needs the operator
/// to read passages aloud and writes a corpus that is then reused unattended, which is a
/// different shape of tool from one that pokes at a single stage.
@main
struct UttrflowEvalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uttrflow-eval",
        abstract: "Measure how well Uttrflow hears and how fast it answers.",
        subcommands: [RecordCorpus.self, PullCorpus.self, TranscribeCorpus.self]
    )
}
