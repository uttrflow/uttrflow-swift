// The `learning-curve` command: the per-speaker confusion learning curve on a local slice of accented read speech.
import ArgumentParser
private import UttrflowEval

/// Decodes a manifest of local clips and prints, per level and k, top-1 recall, false overrides and stored size.
struct LearningCurve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "learning-curve",
        abstract:
            "Measure whether learning one speaker's confusions ranks the meant word better than the global key.",
        discussion: """
            The manifest is the one `harvest-confusions` reads: audio path, reference text, first-language \
            group, speaker. Each speaker is held out in turn; the global key is fitted on the others.
            """
    )

    @Option(name: .long, help: "The tab-separated manifest of local clips.")
    var manifest: String

    @Option(name: .long, help: "The seed for poisoning and the speaker resampling.")
    var seed: UInt64 = 1

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    func run() async throws {
        let (_, utterances) = try await ManifestDecoder.decode(manifest: manifest, modelVariant: modelVariant)
        let speakers = ConfusionLearningCurve.events(utterances)
        print(
            "\(utterances.count) clips; \(speakers.count) speakers; \(speakers.values.joined().count) substitutions"
        )
        print(ConfusionLearningCurve.markdown(ConfusionLearningCurve.curve(speakers, seed: seed)))
    }
}
