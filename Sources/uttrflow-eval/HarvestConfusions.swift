// The `harvest-confusions` command: decodes a local slice of accented read speech into a word-pair table.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
internal import UttrflowEval
private import UttrflowSpeech

/// Reads a manifest of locally downloaded clips, decodes each, and writes only word pairs and class counts.
struct HarvestConfusions: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "harvest-confusions",
        abstract: "Harvest the recogniser's confusions on accented read speech into a word-pair table.",
        discussion: """
            The manifest is a tab-separated file with one clip per line: audio path, reference text, \
            first-language group, speaker. Speakers and sentences are read but never written.
            """
    )

    @Option(name: .long, help: "The tab-separated manifest of local clips.")
    var manifest: String

    @Option(name: .long, help: "Where the table is written, as JSON.")
    var output = ".uttrflow-eval/confusions.json"

    @Option(name: .long, help: "The dataset's name, written into the table.")
    var dataset: String

    @Option(name: .customLong("dataset-version"), help: "The dataset's version or release.")
    var datasetVersion: String

    @Option(name: .long, help: "The dataset's licence.")
    var licence: String

    @Option(name: .long, help: "The seed that splits speakers into the table half and the held-out half.")
    var seed: UInt64 = 1

    @Option(name: .long, help: "A group read by fewer speakers is merged into 'other'.")
    var minimumSpeakers = 10

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    func run() async throws {
        let (engine, utterances) = try await ManifestDecoder.decode(
            manifest: manifest, modelVariant: modelVariant)
        let provenance = HarvestProvenance(
            dataset: dataset, version: datasetVersion, licence: licence,
            engine: engine,
            seed: seed)
        let built = utterances.filter { !ConfusionHarvest.isHeldOut(speaker: $0.speaker, seed: seed) }
        let heldOut = utterances.filter { ConfusionHarvest.isHeldOut(speaker: $0.speaker, seed: seed) }
        let table = ConfusionHarvest.table(built, provenance: provenance, minimumSpeakers: minimumSpeakers)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let destination = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(table).write(to: destination)
        let coverage = ConfusionHarvest.coverage(of: table, on: heldOut)
        print("\(utterances.count) clips; \(table.pairs.count) pairs; digest \(table.digest)")
        print("Held-out coverage: \(coverage.map { String(format: "%.1f%%", $0 * 100) } ?? "–")")
        print("Wrote \(destination.path)")
    }
}

/// Decodes a tab-separated manifest of local clips (audio path, reference, first-language group, speaker) with the shipping path.
enum ManifestDecoder {
    static func decode(
        manifest: String, modelVariant: String?
    ) async throws -> (engine: String, utterances: [HarvestUtterance]) {
        let model =
            try modelVariant.map { name in
                guard let found = SpeechModel.named(name) else {
                    throw ValidationError("Unknown model '\(name)'.")
                }
                return found
            } ?? .default
        let store = FileSystemSpeechModelStore.whisperKit()
        guard store.isInstalled(model) else {
            throw CleanExit.message("\(model.variant) is not installed. Run: uttrflow-dev models install")
        }
        let speech = SpeechEngineFactory.make(
            kind: .whisperKit, model: model, modelFolder: store.location(of: model))
        try await speech.prepare()

        let base = URL(fileURLWithPath: manifest).deletingLastPathComponent()
        let lines = try String(contentsOfFile: manifest, encoding: .utf8).split(separator: "\n")
        var utterances: [HarvestUtterance] = []
        for (index, line) in lines.enumerated() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { continue }
            Terminal.show("\r  \(index + 1) of \(lines.count)          ")
            let url = URL(fileURLWithPath: fields[0], relativeTo: base)
            let audio = try AudioFileReader.read(contentsOf: url)
            let transcription = try await speech.transcribe(audio, options: .automatic)
            utterances.append(
                HarvestUtterance(
                    reference: TextNormaliser.standard.words(fields[1]),
                    recognised: TextNormaliser.standard.words(transcription.text), group: fields[2],
                    speaker: fields[3]))
        }
        Terminal.clearLine()
        return ("whisperKit \(model.variant)", utterances)
    }
}
