// The `confusable-pairs` command: how often the recogniser writes the costly other reading of a confusable pair.
import ArgumentParser
private import Foundation
private import UttrflowAI
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Reads every pair both ways in synthetic voices, at three rates and three noise levels, and tabulates the flips.
struct ConfusablePairsProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "confusable-pairs",
        abstract: "Measure the raw error rate of each high-cost confusable pair, by cost class."
    )

    @Option(name: .long, help: "Where the generated clips are written.")
    var clipsPath = ".uttrflow-eval/confusable-clips"

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Synthetic voices that read the sentences.")
    var voices = ["Samantha", "Rishi"]

    @Option(name: .long, parsing: .upToNextOption, help: "Speaking rates, in words per minute.")
    var rates = [150, 190, 240]

    @Option(name: .long, parsing: .upToNextOption, help: "Signal-to-noise ratios in dB; 'inf' is clean.")
    var snrs: [Double] = [.infinity, 20, 10]

    @Option(name: .long, help: "The rate the clips are synthesised at.")
    var inputRate = 48_000.0

    @Option(name: .long, help: "Where each model stage runs: shipping, gpu, neuralEngine, all or cpu.")
    var compute = SpeechComputePlan.shipping.rawValue

    func run() async throws {
        guard let plan = SpeechComputePlan(rawValue: compute) else {
            throw ValidationError("Unknown compute plan '\(compute)'.")
        }
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
            kind: .whisperKit, model: model, modelFolder: store.location(of: model), compute: plan)
        try await speech.prepare()
        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print(
            "whisperKit \(model.variant), compute \(compute); voices \(voices.joined(separator: ", ")); rates \(rates) wpm; "
                + "noise \(snrs.map(label).joined(separator: ", "))")

        var byPair: [Int: ConfusablePairs.Tally] = [:]
        var byCell: [String: ConfusablePairs.Tally] = [:]
        var written: [Int: [String: Int]] = [:]
        for (index, pair) in ConfusablePairs.all.enumerated() {
            let cost = ConfusionCost.of(heard: pair.firstReading, candidate: pair.secondReading)
            Terminal.show("\r  \(pair.group.rawValue) \(pair.first)/\(pair.second)          ")
            for (spoken, other) in [
                (pair.firstReading, pair.secondReading), (pair.secondReading, pair.firstReading),
            ] {
                let meant = TextNormaliser.standard.words(spoken)
                let otherWords = TextNormaliser.standard.words(other)
                for voice in voices {
                    for rate in rates {
                        let clean = try clip(spoken, voice: voice, rate: rate, in: directory)
                        for snr in snrs {
                            let samples = snr.isInfinite ? clean : WhiteNoise.added(clean, snr: snr)
                            let transcription = try await speech.transcribe(
                                .canonical(samples),
                                options: TranscriptionOptions(languageHint: nil, vocabulary: []))
                            let heard = transcription.scoredWords.map(\.word)
                            let outcome = ConfusablePairs.outcome(
                                meant: meant, other: otherWords, heard: heard)
                            byPair[index, default: .init()].add(outcome)
                            for key in [
                                "\(cost)|all|all", "\(cost)|\(rate)|all", "\(cost)|all|\(label(snr))",
                            ] {
                                byCell[key, default: .init()].add(outcome)
                            }
                            if outcome != .right {
                                written[index, default: [:]][heard.joined(separator: " "), default: 0] += 1
                            }
                        }
                    }
                }
            }
        }
        Terminal.clearLine()
        print("\n| Group | Pair | Cost class | Decodes | Flip rate | Error rate | Most written when wrong |")
        print("|---|---|---|---|---|---|---|")
        for (index, pair) in ConfusablePairs.all.enumerated() {
            let tally = byPair[index] ?? .init()
            let cost = ConfusionCost.of(heard: pair.firstReading, candidate: pair.secondReading)
            let top =
                (written[index] ?? [:]).max { $0.value < $1.value }.map { "\"\($0.key)\" ×\($0.value)" } ?? ""
            let second = pair.second.isEmpty ? "(dropped)" : pair.second
            print(
                "| \(pair.group.rawValue) | \(pair.first) / \(second) | \(cost) | \(tally.decodes) | "
                    + "\(share(tally.flipRate)) | \(share(tally.errorRate)) | \(top) |")
        }
        print("\n| Cost class | Rate | Noise | Decodes | Flip rate | Error rate |")
        print("|---|---|---|---|---|---|")
        let columns = [("all", "all")] + rates.map { ("\($0)", "all") } + snrs.map { ("all", label($0)) }
        for cost in ConfusionCost.allCases {
            for (rate, noise) in columns {
                guard let tally = byCell["\(cost)|\(rate)|\(noise)"] else { continue }
                print(
                    "| \(cost) | \(rate) | \(noise) | \(tally.decodes) | \(share(tally.flipRate)) | "
                        + "\(share(tally.errorRate)) |")
            }
        }
    }

    private func label(_ snr: Double) -> String { snr.isInfinite ? "clean" : "\(Int(snr)) dB" }

    private func share(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }

    /// The sentence read by `voice` at `rate`, synthesised once and reused.
    private func clip(_ text: String, voice: String, rate: Int, in directory: URL) throws -> [Float] {
        let url = directory.appendingPathComponent(
            "\(voice)-\(rate)-\(String(text.hashValueStable, radix: 16)).wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = [
                "-v", voice, "-r", "\(rate)", "-o", url.path, "--data-format=LEF32@\(Int(inputRate))", text,
            ]
            try say.run()
            say.waitUntilExit()
            guard say.terminationStatus == 0 else {
                throw CleanExit.message("say failed for voice \(voice).")
            }
        }
        return try AudioFileReader.read(contentsOf: url).samples
    }
}
