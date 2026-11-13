// The `persona-eval` command: the persona's words handed to the recogniser off, on and wrong.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Has a voice read invented sentences and decodes each with no persona words, its own and another's. See `Docs/eval-methodology.md`.
struct PersonaEvaluationCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "persona-eval",
        abstract: "Measure the gain from a persona's words and the harm from another persona's."
    )

    @Option(name: .long, help: "Where the synthesised clips are kept between runs.")
    var clipsPath = FileManager.default.temporaryDirectory.appendingPathComponent("persona-eval-clips").path

    @Option(name: .long, help: "The `say` voice that reads every sentence.")
    var voice = "Samantha"

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
        var rows: [PersonaRow] = []
        for (index, item) in PersonaCorpus.items.enumerated() {
            Terminal.show("\r  \(index + 1)/\(PersonaCorpus.items.count)")
            let fingerprint = (voice + item.sentence).utf8.reduce(0xcbf2_9ce4_8422_2325 as UInt64) {
                ($0 ^ UInt64($1)) &* 0x100_0000_01b3
            }
            let clip = directory.appendingPathComponent("\(String(fingerprint, radix: 16)).wav")
            if !FileManager.default.fileExists(atPath: clip.path) {
                guard SaySynthesizer().speak(item.sentence, voice: voice, to: clip) else {
                    throw CleanExit.message("`say` could not read clip \(index + 1) in \(voice).")
                }
            }
            let audio = try AudioFileReader.read(contentsOf: clip)
            for condition in PersonaCondition.allCases {
                let heard = try await speech.transcribe(
                    audio,
                    options: TranscriptionOptions(
                        languageHint: .english,
                        vocabulary: PersonaCorpus.vocabulary(for: item, under: condition)))
                rows.append(PersonaRow(item: item, condition: condition, transcript: heard.text))
            }
        }
        Terminal.clearLine()
        let report = PersonaReport(rows: rows)
        print(report.markdown)
        if !report.harmed.isEmpty { throw ExitCode.failure }
    }
}
