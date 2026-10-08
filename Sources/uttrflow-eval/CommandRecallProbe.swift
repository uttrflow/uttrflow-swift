// The `command-recall` command: the command corpus's metrics, and each Markdown command phrase heard on synthesised audio.
import ArgumentParser
private import Foundation
private import UttrflowAI
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Scores the command corpus with the shipped reader and router, then each command phrase read by synthetic voices.
struct CommandRecallProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "command-recall",
        abstract:
            "Measure command recall and false execution, and gate recall of each command phrase on audio."
    )

    @Option(name: .long, help: "Where the synthesised clips are written.")
    var clipsPath = ".uttrflow-eval/command-clips"

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Synthetic voices that read every phrase.")
    var voices = ["Samantha", "Daniel", "Karen", "Rishi", "Moira", "Tessa"]

    @Option(name: .long, parsing: .upToNextOption, help: "Signal-to-noise ratios in dB; 'inf' is clean.")
    var snrs: [Double] = [.infinity, 20, 10]

    @Option(
        name: .long, help: "A file to write every take to: command, voice, SNR in dB and text, tab-separated."
    )
    var record: String?

    func validate() throws {
        if voices.isEmpty { throw ValidationError("--voices needs at least one voice.") }
        if snrs.isEmpty { throw ValidationError("--snrs needs at least one level.") }
    }

    func run() async throws {
        try await corpus()
        let report = CommandAudioReport(takes: try await takes(), reads: MarkdownCommand.edit(for:on:))
        print("\n| Command | Takes | Recall | Misfires |")
        print("|---|---|---|---|")
        for row in report.rows {
            print("| \(row.commandID) | \(row.takes) | \(percent(row.recall)) | \(row.misfires) |")
        }
        print("\n| Condition | Recall |")
        print("|---|---|")
        for snr in snrs { print("| \(label(snr)) | \(percent(report.recall { $0.snr == snr })) |") }
        for voice in voices { print("| \(voice) | \(percent(report.recall { $0.voice == voice })) |") }
        print("| all | \(percent(report.recall)) |")
        for take in report.misfires { print("  misfire: \(take.commandID) heard as '\(take.heard)'") }
        for take in report.missed where !report.misfires.contains(take) {
            print("  missed: \(take.commandID), \(take.voice), \(label(take.snr)): '\(take.heard)'")
        }
        guard report.passesGate else {
            print(
                "Below the gate: recall floor \(percent(CommandAudioReport.recallFloor)), "
                    + "misfire ceiling \(CommandAudioReport.misfireCeiling).")
            throw ExitCode.failure
        }
    }

    /// The text corpus: the command key's cases through the shipped reader, and the mentions through the shipped router.
    private func corpus() async throws {
        let router = TextTransformers.router()
        var dictated: [String: String] = [:]
        for mention in EvaluationCorpus.commandMentions {
            dictated[mention.id] = try await router.transform(mention.transformationRequest()).text
        }
        let report = CommandReport(reads: MarkdownCommand.edit(for:on:)) { dictated[$0.id] ?? $0.spoken }
        print("| Command | Must run | Ran | Must not run | Ran anyway | Mentions | Mentions run |")
        print("|---|---|---|---|---|---|---|")
        for row in report.rows {
            print(
                "| \(row.commandID) | \(row.wanted) | \(row.ran) | \(row.content) | \(row.falseRuns) "
                    + "| \(row.mentioned) | \(row.mentionRuns) |")
        }
        for (document, count) in report.falseRunsByDocument.sorted(by: { $0.key < $1.key }) {
            print("  false runs in \(document): \(count)")
        }
        for mention in report.mentionExecutions {
            print("  mention run: \(mention.id) wrote '\(dictated[mention.id] ?? "")'")
        }
        print("Text gate: \(report.passesGate ? "pass" : "fail")")
        if !report.passesGate { throw ExitCode.failure }
    }

    /// Every Markdown command phrase read by every voice under every noise level, and what the recogniser wrote.
    private func takes() async throws -> [CommandTake] {
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
        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print(
            "\nwhisperKit \(model.variant); voices \(voices.joined(separator: ", ")); noise \(snrs.map(label))"
        )
        var takes: [CommandTake] = []
        for row in SpokenCommands.markdown {
            let phrase = row.words.joined(separator: " ")
            for voice in voices {
                let clean = try clip(phrase, voice: voice, in: directory)
                for snr in snrs {
                    Terminal.show("\r  \(row.id) \(voice) \(label(snr))          ")
                    let samples = snr.isInfinite ? clean : WhiteNoise.added(clean, snr: snr)
                    let heard = try await speech.transcribe(
                        .canonical(samples), options: TranscriptionOptions(languageHint: nil, vocabulary: [])
                    ).text.trimmingCharacters(in: .whitespacesAndNewlines)
                    takes.append(CommandTake(commandID: row.id, voice: voice, snr: snr, heard: heard))
                }
            }
        }
        Terminal.clearLine()
        if let record {
            let lines = takes.map { "\($0.commandID)\t\($0.voice)\t\($0.snr)\t\($0.heard)" }
            try (lines.joined(separator: "\n") + "\n").write(
                toFile: record, atomically: true, encoding: .utf8)
        }
        return takes
    }

    private func label(_ snr: Double) -> String { snr.isInfinite ? "clean" : "\(Int(snr)) dB" }

    private func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }

    /// `text` read by `voice` into a file, synthesised once and reused on later runs; never played.
    private func clip(_ text: String, voice: String, in directory: URL) throws -> [Float] {
        let url = directory.appendingPathComponent(
            "\(voice)-\(text.replacingOccurrences(of: " ", with: "_")).wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", voice, "-o", url.path, "--data-format=LEF32@16000", text]
            try say.run()
            say.waitUntilExit()
            guard say.terminationStatus == 0 else {
                throw CleanExit.message("say failed for voice \(voice).")
            }
        }
        return try AudioFileReader.read(contentsOf: url).samples
    }
}
