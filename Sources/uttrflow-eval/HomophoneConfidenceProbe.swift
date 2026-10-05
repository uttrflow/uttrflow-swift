// The `homophone-confidence` command: whether the recogniser's word score drops when it writes the wrong homophone.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Decodes invented homophone sentences in synthetic voices and tabulates the score of the meant word's slot.
struct HomophoneConfidenceProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "homophone-confidence",
        abstract: "Measure whether a misheard homophone scores under the correction gate."
    )

    @Option(name: .long, help: "Where the generated clips are written.")
    var clipsPath = ".uttrflow-eval/homophone-clips"

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Synthetic voices that read the sentences.")
    var voices = ["Samantha", "Daniel", "Karen"]

    @Option(name: .long, parsing: .upToNextOption, help: "Speaking rates, in words per minute.")
    var rates = [175, 230]

    @Option(name: .long, help: "The rate the clips are synthesised at.")
    var inputRate = 48_000.0

    /// One cell of the condition matrix.
    struct Condition: Hashable {
        let prefixed: Bool
        let prompted: Bool
    }

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
        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let groups = [
            ("programmer", HomophoneConfidence.programmerPairs),
            ("ordinary", HomophoneConfidence.ordinaryPairs),
        ]
        let conditions = [false, true].flatMap { prefixed in
            [false, true].map { Condition(prefixed: prefixed, prompted: $0) }
        }
        print("whisperKit \(model.variant); voices \(voices.joined(separator: ", ")); rates \(rates) wpm")
        var byPair: [String: [HomophoneConfidence.Outcome]] = [:]
        var byCell: [String: [Condition: [HomophoneConfidence.Outcome]]] = [:]
        var wrongWords: [String: [String: Int]] = [:]
        for (group, pairs) in groups {
            for pair in pairs {
                Terminal.show("\r  \(group) \(pair.meant)          ")
                for voice in voices {
                    for rate in rates {
                        for condition in conditions {
                            let text =
                                condition.prefixed
                                ? HomophoneConfidence.developerPrefix + " " + pair.sentence : pair.sentence
                            let samples = try clip(text, voice: voice, rate: rate, in: directory)
                            let options = TranscriptionOptions(
                                languageHint: nil, vocabulary: condition.prompted ? [pair.meant] : [])
                            let transcription = try await speech.transcribe(
                                .canonical(samples), options: options)
                            let reference = TextNormaliser.standard.words(text)
                            guard let index = reference.lastIndex(of: pair.meant) else { continue }
                            let outcome = HomophoneConfidence.outcome(
                                reference: reference, index: index, heard: scoredWords(transcription))
                            byPair[pair.meant, default: []].append(outcome)
                            byCell[group, default: [:]][condition, default: []].append(outcome)
                            if case .wrong(let heard, _) = outcome {
                                wrongWords[pair.meant, default: [:]][heard, default: 0] += 1
                            }
                            if case .dropped = outcome {
                                wrongWords[pair.meant, default: [:]]["(dropped)", default: 0] += 1
                            }
                        }
                    }
                }
            }
        }
        Terminal.clearLine()
        print(
            "\n| Pair | Decodes | Error rate | Median score when wrong | Wrong below 0.5 | Right below 0.5 | AUC | Written instead |"
        )
        print("|---|---|---|---|---|---|---|---|")
        for (_, pairs) in groups {
            for pair in pairs {
                let row = HomophoneConfidence.summary(byPair[pair.meant] ?? [])
                let instead = (wrongWords[pair.meant] ?? [:]).sorted { $0.value > $1.value }
                    .map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")
                print("| \(pair.meant) / \(pair.other) | " + cells(row) + " | \(instead) |")
            }
        }
        print(
            "\n| Group | Prefix | Term in prompt | Decodes | Error rate | Median score when wrong | Wrong below 0.5 | Right below 0.5 | AUC |"
        )
        print("|---|---|---|---|---|---|---|---|---|")
        for (group, _) in groups {
            for condition in conditions {
                let row = HomophoneConfidence.summary(byCell[group]?[condition] ?? [])
                print(
                    "| \(group) | \(condition.prefixed ? "yes" : "no") | \(condition.prompted ? "yes" : "no") | "
                        + cells(row) + " |")
            }
            let all = HomophoneConfidence.summary(byCell[group]?.values.flatMap { $0 } ?? [])
            print("| \(group) | all | all | " + cells(all) + " |")
        }
    }

    /// Every word the engine wrote, normalised, with the score of the recognised word it came from.
    private func scoredWords(_ transcription: Transcription) -> [(word: String, score: Double)] {
        transcription.segments.flatMap(\.words).flatMap { word in
            TextNormaliser.standard.words(word.text).map { (word: $0, score: word.confidence) }
        }
    }

    /// The sentence read by `voice` at `rate`, synthesised once and reused.
    private func clip(_ text: String, voice: String, rate: Int, in directory: URL) throws -> [Float] {
        let name = "\(voice)-\(rate)-\(String(text.hashValueStable, radix: 16)).wav"
        let url = directory.appendingPathComponent(name)
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

    private func cells(_ row: HomophoneConfidence.Summary) -> String {
        func share(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0 * 100) } ?? "–" }
        func score(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "–" }
        return [
            "\(row.decodes)", share(row.errorRate), score(row.medianWrongScore), share(row.wrongBelowGate),
            share(row.rightBelowGate), score(row.auc),
        ].joined(separator: " | ")
    }
}

extension String {
    /// A hash that is the same on every run, unlike `hashValue`, so clip file names are reused.
    fileprivate var hashValueStable: UInt64 {
        utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}
