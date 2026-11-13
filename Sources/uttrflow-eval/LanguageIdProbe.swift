// The `language-id` command: how often each reading's language is detected right, by clip length.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Has synthetic voices read corpus sentences and scores the language the recogniser detects for each clip.
struct LanguageIdProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "language-id",
        abstract: "Measure language identification by clip length, as a confusion matrix per reading."
    )

    @Option(name: .long, help: "Where the synthesised clips are kept between runs.")
    var clipsPath = ".uttrflow-eval/language-id-clips"

    @Option(name: .long, help: "Where each clip's detection is written, one tab-separated row per clip.")
    var rowsPath = ".uttrflow-eval/language-id-rows.tsv"

    @Option(name: .long, parsing: .upToNextOption, help: "The Indian English `say` voices.")
    var indianVoices = ["Aman", "Rishi", "Tara"]

    @Option(name: .long, parsing: .upToNextOption, help: "The other English `say` voices.")
    var otherVoices = ["Samantha"]

    @Option(name: .long, help: "The Hindi `say` voice.")
    var hindiVoice = "Lekha"

    @Option(name: .long, help: "English sentences taken per word-count band, so short ones are not swamped.")
    var perBand = 20

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
            let why = store.whyNotInstalled(model) ?? "it is not installed"
            throw CleanExit.message("\(model.variant): \(why). Run: uttrflow-dev models install")
        }
        let installed = SayVoiceCatalogue().installedVoiceNames()
        let missing = (indianVoices + otherVoices + [hindiVoice]).filter { !installed.contains($0) }
        guard missing.isEmpty else {
            throw CleanExit.message("Not installed: \(missing.joined(separator: ", ")); see `say -v ?`.")
        }
        let speech = SpeechEngineFactory.make(
            kind: .whisperKit, model: model, modelFolder: store.location(of: model))
        try await speech.prepare()
        print("Engine: whisperKit \(model.variant) weights \(model.weightsRevision), detection with no hint")

        let readings = Self.readings(
            english: Self.englishSample(perBand: perBand), hindi: Self.hindiCases,
            indianVoices: indianVoices, otherVoices: otherVoices, hindiVoice: hindiVoice)
        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var rows: [LanguageIdentification] = []
        var lines: [String] = []
        for (index, reading) in readings.enumerated() {
            Terminal.show("\r  \(index + 1)/\(readings.count)")
            let clip = directory.appendingPathComponent(
                "\(reading.voice.filter(\.isLetter))-\(reading.id).wav")
            if !FileManager.default.fileExists(atPath: clip.path) {
                guard SaySynthesizer().speak(reading.text, voice: reading.voice, to: clip) else {
                    throw CleanExit.message("`say` could not read \(reading.id) in \(reading.voice).")
                }
            }
            let audio = try AudioFileReader.read(contentsOf: clip)
            let heard = try await speech.transcribe(audio, options: .automatic).detectedLanguage
            let seconds = Double(audio.samples.count) / Double(audio.sampleRate)
            let row = LanguageIdentification(
                group: reading.group, expected: reading.expected, detected: heard?.code.value,
                probability: heard?.confidence, seconds: seconds)
            rows.append(row)
            lines.append(
                [
                    reading.group, reading.voice, reading.id, String(format: "%.2f", seconds),
                    row.detected ?? "none",
                    row.probability.map { String(format: "%.3f", $0) } ?? "n/a",
                ].joined(separator: "\t"))
        }
        Terminal.clearLine()
        try lines.joined(separator: "\n").write(
            to: URL(fileURLWithPath: rowsPath), atomically: true, encoding: .utf8)
        let matrix = LanguageIdentificationMatrix(rows)
        print(matrix.markdown)
        let over = matrix.cellsOverLimit.map { "\($0.group), \($0.bucket.rawValue)" }
        let limit = Int(LanguageIdentificationMatrix.errorLimit * 100)
        print("Cells above \(limit)% error: \(over.isEmpty ? "none" : over.joined(separator: "; "))")
    }

    /// One clip to synthesise: what is read, by whom, and the language it should be detected as.
    private struct Reading {
        let id: String
        let text: String
        let voice: String
        let group: String
        let expected: String
    }

    /// The corpus's Hindi cases, read in Devanagari as spoken.
    private static var hindiCases: [EvaluationCase] {
        EvaluationCorpus.all.filter { $0.language == .hindi }.sorted { $0.id < $1.id }
    }

    /// English cases by id, at most `perBand` from each word-count band, so short sentences are well sampled.
    private static func englishSample(perBand: Int) -> [EvaluationCase] {
        let english = EvaluationCorpus.all.filter { $0.language == .english }.sorted { $0.id < $1.id }
        let bands: [ClosedRange<Int>] = [1...2, 3...5, 6...12, 13...Int.max]
        return bands.flatMap { band in
            english.filter { band.contains($0.spoken.split(separator: " ").count) }.prefix(perBand)
        }
    }

    /// Each English case in each English voice and each Hindi case in the Hindi voice, grouped by reading.
    private static func readings(
        english: [EvaluationCase], hindi: [EvaluationCase], indianVoices: [String], otherVoices: [String],
        hindiVoice: String
    ) -> [Reading] {
        let indian = indianVoices.flatMap { voice in
            english.map {
                Reading(id: $0.id, text: $0.spoken, voice: voice, group: "en, en-IN voice", expected: "en")
            }
        }
        let other = otherVoices.flatMap { voice in
            english.map {
                Reading(id: $0.id, text: $0.spoken, voice: voice, group: "en, other voice", expected: "en")
            }
        }
        let hindiReadings = hindi.map { item in
            // A Hindi sentence with English words in Latin letters is code-mixed, and is scored on its own.
            let mixed = item.spoken.unicodeScalars.contains {
                ("a"..."z").contains($0) || ("A"..."Z").contains($0)
            }
            return Reading(
                id: item.id, text: item.spoken, voice: hindiVoice, group: mixed ? "hi+en" : "hi",
                expected: "hi")
        }
        return indian + other + hindiReadings
    }
}
