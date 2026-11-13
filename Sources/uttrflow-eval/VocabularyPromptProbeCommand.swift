// The `vocabulary-prompt` command: the recogniser's vocabulary prompt measured on Hindi speech under each language hint.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Has a Hindi voice read invented sentences and decodes each under every hint and prompt condition. See `Docs/vocabulary-prompt-hindi.md`.
struct VocabularyPromptProbeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vocabulary-prompt",
        abstract:
            "Measure the vocabulary prompt on Hindi speech: script kept, names heard, word errors."
    )

    @Option(name: .long, help: "Where the synthesised clips are kept between runs.")
    var clipsPath = FileManager.default.temporaryDirectory.appendingPathComponent("vocabulary-prompt-clips")
        .path

    @Option(
        name: .long,
        help: "Where each transcript is written, one tab-separated row per clip, hint and prompt.")
    var rowsPath = FileManager.default.temporaryDirectory.appendingPathComponent("vocabulary-prompt-rows.tsv")
        .path

    @Option(name: .long, help: "The `say` voice that reads every sentence.")
    var voice = "Lekha"

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

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
        guard SayVoiceCatalogue().installedVoiceNames().contains(voice) else {
            throw CleanExit.message("Not installed: \(voice); `say -v ?` lists those that are.")
        }
        let speech = SpeechEngineFactory.make(
            kind: .whisperKit, model: model, modelFolder: store.location(of: model))
        try await speech.prepare()
        print("Engine: whisperKit \(model.variant) weights \(model.weightsRevision); voice \(voice)")

        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let items = VocabularyPromptCorpus.items
        var rows: [VocabularyPromptRow] = []
        for (index, item) in items.enumerated() {
            Terminal.show("\r  \(index + 1)/\(items.count)")
            let clip = directory.appendingPathComponent("\(voice.filter(\.isLetter))-\(item.id).wav")
            if !FileManager.default.fileExists(atPath: clip.path) {
                guard SaySynthesizer().speak(item.sentence, voice: voice, to: clip) else {
                    throw CleanExit.message("`say` could not read \(item.id) in \(voice).")
                }
            }
            let audio = try AudioFileReader.read(contentsOf: clip)
            for hint in ["hi", "auto"] {
                for condition in VocabularyPromptCondition.allCases {
                    let prompt = condition.prompt(for: item)
                    let options = TranscriptionOptions(
                        languageHint: hint == "auto" ? nil : LanguageCode(hint),
                        vocabulary: prompt.vocabulary,
                        precedingText: prompt.precedingText)
                    let text = try await speech.transcribe(audio, options: options).text
                    rows.append(
                        VocabularyPromptRow(item: item, hint: hint, condition: condition, transcript: text))
                }
            }
        }
        Terminal.clearLine()
        let lines = rows.map {
            [$0.item.id, $0.hint, $0.condition.rawValue, $0.transcript].joined(separator: "\t")
        }
        try lines.joined(separator: "\n").write(
            to: URL(fileURLWithPath: rowsPath), atomically: true, encoding: .utf8)
        print(VocabularyPromptTable(rows: rows).markdown)
    }
}
