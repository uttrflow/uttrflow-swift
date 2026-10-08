// The `explain` command: replays a recorded clip and prints what each stage decided.
import ArgumentParser
import Foundation
import UttrflowAI
import UttrflowAudio
import UttrflowCore
import UttrflowPipeline
import UttrflowSpeech

/// Transcribes and tidies one recorded clip, printing what every stage decided to the terminal only.
struct Explain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Replay a recorded clip and show what each stage of dictation decided."
    )

    @Argument(help: "A recorded clip to replay, e.g. one made with `uttrflow-dev record`.")
    var file: String

    @Option(name: .shortAndLong, help: "Bias towards a language, e.g. en or hi. Omit to detect.")
    var language: String?

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Flag(
        name: .long,
        help: "Cut the clip where the app cuts a finished recording, and trace each piece and the join.")
    var pieces = false

    @OptionGroup var modelsDirectory: ModelsDirectoryOptionGroup

    func validate() throws {
        if let language, LanguageCode(language) == nil {
            throw ValidationError("'\(language)' is not a language code.")
        }
    }

    func run() async throws {
        let model = try resolve(modelVariant)
        let store = try modelsDirectory.store()
        guard store.isInstalled(model) else {
            throw CleanExit.message("\(model.variant) is not installed. Run: uttrflow-dev models install")
        }
        let audio = try AudioFileReader.read(contentsOf: URL(fileURLWithPath: file))
        guard !audio.isEmpty else { throw CleanExit.message("The file holds no audio.") }

        let speech = SpeechEngineFactory.make(
            kind: .whisperKit, model: model, modelFolder: store.location(of: model))
        try await speech.prepare()
        guard !pieces else { return try await tracePieces(of: audio, through: speech) }
        let transcription = try await speech.transcribe(
            audio, options: TranscriptionOptions(languageHint: language.flatMap(LanguageCode.init)))
        guard !transcription.isBlank else { throw CleanExit.message("Nothing was recognised.") }

        let explanation = try await DictationExplanation.tracing(
            TransformationRequest(transcription: transcription), through: TextTransformers.router())
        for line in explanation.lines { print("  \(line)") }
    }

    /// Recognises each piece the app's windowing cuts, then cleans them through the pipeline's own piece path.
    private func tracePieces(of audio: AudioSamples, through speech: any SpeechEngine) async throws {
        let options = TranscriptionOptions(languageHint: language.flatMap(LanguageCode.init))
        var heard: [Transcription] = []
        for window in SpeechWindowing.standard.windows(
            in: audio.samples, sampleRate: audio.sampleRate, boundaries: audio.discontinuities)
        {
            let piece = try await speech.transcribe(
                .canonical(Array(audio.samples[window])), options: options)
            if !piece.isBlank { heard.append(piece) }
        }
        guard !heard.isEmpty else { throw CleanExit.message("Nothing was recognised.") }
        let trace = await Seams.pipeline(cleaning: TextTransformers.router()).trace(
            heard, seeing: AppContext())
        for line in trace.lines { print("  \(line)") }
    }
}
