// The `token-cap` command: how often a long Hindi piece runs the decoder out of positions.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Has a Hindi voice read growing runs of the corpus's passages and decodes each as one piece. See `Docs/hindi-token-cap.md`.
struct TokenCapProbeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "token-cap",
        abstract:
            "Measure how often a Hindi piece reaches the decoder's token cap, and the recovery it needs."
    )

    @Option(name: .long, help: "Where the synthesised clips are kept between runs.")
    var clipsPath = FileManager.default.temporaryDirectory.appendingPathComponent("token-cap-clips").path

    @Option(name: .long, help: "The `say` voice that reads every piece.")
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
        let pieces = TokenCapPiece.growing(from: TranscriptionCorpus.all)
        var rows: [TokenCapRow] = []
        for (index, piece) in pieces.enumerated() {
            Terminal.show("\r  \(index + 1)/\(pieces.count)")
            let clip = directory.appendingPathComponent("\(voice.filter(\.isLetter))-\(piece.id).wav")
            if !FileManager.default.fileExists(atPath: clip.path) {
                guard SaySynthesizer().speak(piece.text, voice: voice, to: clip) else {
                    throw CleanExit.message("`say` could not read \(piece.id) in \(voice).")
                }
            }
            let audio = try AudioFileReader.read(contentsOf: clip)
            let heard = try await speech.transcribe(
                audio, options: TranscriptionOptions(languageHint: .hindi))
            rows.append(
                TokenCapRow(
                    piece: piece, audioSeconds: audio.duration.inSeconds,
                    transcriptWords: heard.text.split(whereSeparator: \.isWhitespace).count,
                    effort: heard.effort))
        }
        Terminal.clearLine()
        for row in rows {
            print(
                "\(row.piece.id)\t\(String(format: "%.1f", row.audioSeconds)) s\t\(row.piece.words) words\t"
                    + "\(row.transcriptWords) heard\truns \(row.effort.encoderRuns)\t"
                    + "again \(String(format: "%.1f", row.effort.retrySeconds)) s\t"
                    + (row.effort.capUnresolved ? "unresolved" : row.reachedCap ? "cap" : "-"))
        }
        print(TokenCapTable(rows: rows).markdown)
    }
}
