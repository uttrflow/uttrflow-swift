// The `names` command: how the recogniser spells names by origin and band, with and without the dictionary.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Has synthetic voices read every name in its carrier, and scores it plain and in the vocabulary prompt.
struct NameClassProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "names",
        abstract: "Measure name spelling by origin and frequency band. See Docs/eval-methodology.md."
    )

    @Option(name: .long, help: "Where the synthesised clips are kept between runs.")
    var clipsPath = ".uttrflow-eval/name-clips"

    @Option(name: .long, help: "Where each heard name is written, one tab-separated row per clip and prompt.")
    var rowsPath = ".uttrflow-eval/name-rows.tsv"

    @Option(name: .long, parsing: .upToNextOption, help: "The `say` voices that read every sentence.")
    var voices = ["Samantha", "Rishi"]

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, help: "Where each model stage runs: shipping, gpu, neuralEngine, all or cpu.")
    var compute = SpeechComputePlan.shipping.rawValue

    func run() async throws {
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
        let installed = SayVoiceCatalogue().installedVoiceNames()
        let missing = voices.filter { !installed.contains($0) }
        guard missing.isEmpty else {
            let names = missing.joined(separator: ", ")
            throw CleanExit.message("Not installed: \(names); `say -v ?` lists those that are.")
        }
        guard let plan = SpeechComputePlan(rawValue: compute) else {
            throw ValidationError("Unknown compute plan '\(compute)'.")
        }
        let speech = SpeechEngineFactory.make(
            kind: .whisperKit, model: model, modelFolder: store.location(of: model), compute: plan)
        try await speech.prepare()
        print("Engine: whisperKit \(model.variant) weights \(model.weightsRevision), compute \(compute)")
        print("Voices: \(voices.joined(separator: ", ")); English hint; each name plain and in vocabulary")

        let items = try NameClassCorpus.items()
        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var rows: [NameClassRow] = []
        for voice in voices {
            for (index, item) in items.enumerated() {
                Terminal.show("\r  \(voice) \(index + 1)/\(items.count)")
                let clip = directory.appendingPathComponent("\(voice.filter { $0.isLetter })-\(item.id).wav")
                if !FileManager.default.fileExists(atPath: clip.path) {
                    guard SaySynthesizer().speak(item.sentence, voice: voice, to: clip) else {
                        throw CleanExit.message("`say` could not read \(item.id) in \(voice).")
                    }
                }
                let audio = try AudioFileReader.read(contentsOf: clip)
                for inDictionary in [false, true] {
                    let options = TranscriptionOptions(
                        languageHint: .english, vocabulary: inDictionary ? [item.name] : [])
                    let text = try await speech.transcribe(audio, options: options).text
                    rows.append(
                        NameClassRow(item: item, voice: voice, inDictionary: inDictionary, transcript: text))
                }
            }
        }
        Terminal.clearLine()
        try rows.map(\.line).joined(separator: "\n").write(
            to: URL(fileURLWithPath: rowsPath), atomically: true, encoding: .utf8)
        let report = NameClassReport(rows: rows)
        print(report.originBandTable)
        print("")
        print(report.kindTable)
        print("")
        print("Weakest band, plain: \(report.weakestBand?.rawValue ?? "n/a")")
        print("")
        print(report.confusions)
    }
}
