// The `disfluent-speech` command: the recorded disfluent-speech corpus through the shipping recogniser and clean-up.
import ArgumentParser
private import Foundation
private import UttrflowAI
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Transcribes each recorded take, cleans it as dictation would, and prints the per-pattern report.
struct DisfluentSpeechProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disfluent-speech",
        abstract: "Score the recorded disfluent-speech corpus: meant words lost and disfluency left in.",
        discussion: """
            The folder holds corpus.json and one subfolder of audio per speaker label, as \
            Docs/disfluent-speech.md describes. Nothing is fetched and nothing is written.
            """
    )

    @Option(name: .long, help: "The local corpus folder: corpus.json beside one subfolder per speaker.")
    var corpus: String

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
        let speech = SpeechEngineFactory.make(
            kind: .whisperKit, model: model, modelFolder: store.location(of: model))
        try await speech.prepare()
        let router = TextTransformers.router()
        print("whisperKit \(model.variant); shipping clean-up")
        let lines = try await DisfluentSpeechRun.lines(folder: URL(fileURLWithPath: corpus)) { url in
            let audio = try AudioFileReader.read(contentsOf: url)
            let transcription = try await speech.transcribe(audio, options: .automatic)
            let cleaned = try await router.clean(TransformationRequest(transcription: transcription))
            return DisfluentSpeechRun.Heard(recognised: transcription.text, output: cleaned.text)
        }
        lines.forEach { print($0) }
    }
}
