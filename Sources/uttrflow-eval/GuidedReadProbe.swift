// The `guided-read` command: what one reading of the guided passage measures about each speaker.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Decodes the guided passage read by each voice or recording and prints the speaker measures it yields.
struct GuidedReadProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "guided-read",
        abstract:
            "Measure each speaker's rate, pauses, confidence and missed technical words on the guided passage."
    )

    @Option(name: .long, help: "Where the synthesised readings are kept.")
    var clipsPath = ".uttrflow-eval/guided-read-clips"

    @Option(name: .long, parsing: .upToNextOption, help: "`say` voices that read the passage.")
    var voices = ["Samantha", "Daniel", "Rishi", "Karen"]

    @Option(
        name: .long, parsing: .upToNextOption,
        help: "Recordings of a person reading the passage; each row is named by its file.")
    var recordings: [String] = []

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
        print("Engine: whisperKit \(model.variant) weights \(model.weightsRevision)\n")
        print(
            "| Speaker | Words a minute | Median pause | 90th pause | Median confidence | Pause setting | Missed |"
        )
        print("|---|---|---|---|---|---|---|")
        for (speaker, clip) in try readings() {
            Terminal.show("\r  \(speaker)          ")
            let heard = try await speech.transcribe(
                AudioFileReader.read(contentsOf: clip),
                options: TranscriptionOptions(languageHint: LanguageCode("en")))
            Terminal.clearLine()
            print(row(speaker, GuidedRead.measure(heard.segments.flatMap(\.words))))
        }
    }

    /// Every reading to decode, synthesising a voice's reading once and reusing it after.
    private func readings() throws -> [(speaker: String, clip: URL)] {
        let recorded = recordings.map { path in
            (
                speaker: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                clip: URL(fileURLWithPath: path)
            )
        }
        let installed = SayVoiceCatalogue().installedVoiceNames()
        let missing = voices.filter { !installed.contains($0) }
        guard missing.isEmpty else {
            throw CleanExit.message(
                "Not installed: \(missing.joined(separator: ", ")); `say -v ?` lists those that are.")
        }
        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let spoken = try voices.map { voice in
            let clip = directory.appendingPathComponent("\(voice.filter { $0.isLetter }).wav")
            if !FileManager.default.fileExists(atPath: clip.path),
                !SaySynthesizer().speak(GuidedRead.passage, voice: voice, to: clip)
            {
                throw CleanExit.message("`say` could not read the passage in \(voice).")
            }
            return (speaker: voice, clip: clip)
        }
        return recorded + spoken
    }

    private func row(_ speaker: String, _ read: GuidedRead) -> String {
        func figure(_ value: Double?, _ digits: Int) -> String {
            value.map { String(format: "%.\(digits)f", $0) } ?? "n/a"
        }
        let missed =
            "\(read.missedTargets.count) of \(read.targets.count)"
            + (read.missedTargets.isEmpty ? "" : ": \(read.missedTargets.joined(separator: ", "))")
        let cells = [
            speaker, figure(read.wordsPerMinute, 0), figure(read.medianPause, 2), figure(read.longPause, 2),
            figure(read.medianConfidence, 2), read.pauses?.rawValue ?? "n/a", missed,
        ]
        return "| \(cells.joined(separator: " | ")) |"
    }
}
