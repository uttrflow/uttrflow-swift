// The `short` command: how the shipping speech path handles one-to-three-word replies, by clip length.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Synthesises the short-utterance class at two speaking rates and reports its rates per length bucket.
struct ShortUtteranceProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "short",
        abstract: "Measure one-to-three-word replies: exact matches, invented words, empty and wrong-language output."
    )

    @Option(name: .long, help: "Where the synthesised clips are written and reused.")
    var clipsPath = ".uttrflow-eval/short-clips"

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, help: "Load the model from this folder instead of the model store.")
    var modelFolder: String?

    @Option(name: .long, help: "The `say` voice for English replies.")
    var englishVoice = "Samantha"

    @Option(name: .long, help: "The Indian-English `say` voice that reads the romanised Hindi replies.")
    var hindiVoice = "Rishi"

    @Option(name: .long, parsing: .upToNextOption, help: "Speaking rates in words a minute, one pass each.")
    var rates = [140, 220]

    @Flag(name: .long, help: "Print every clip's transcript.")
    var verbose = false

    func run() async throws {
        let model =
            try modelVariant.map { name in
                guard let found = SpeechModel.named(name) else { throw ValidationError("Unknown model '\(name)'.") }
                return found
            } ?? .default
        let store = FileSystemSpeechModelStore.whisperKit()
        guard modelFolder != nil || store.isInstalled(model) else {
            throw CleanExit.message("\(model.variant) is not installed. Run: uttrflow-dev models install")
        }
        let speech = SpeechEngineFactory.make(
            kind: .whisperKit, model: model,
            modelFolder: modelFolder.map { URL(fileURLWithPath: $0) } ?? store.location(of: model))
        try await speech.prepare()

        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let total = ShortUtterances.all.count * rates.count
        print("Probing \(counted(total, "clip")) with whisperKit \(model.variant)…")
        var byBucket: [ShortUtteranceBucket: [ShortUtteranceScore]] = [:]
        var byKind: [String: [ShortUtteranceScore]] = [:]
        var done = 0
        for rate in rates {
            for utterance in ShortUtterances.all {
                done += 1
                Terminal.show("\r  clip \(done)/\(total)")
                let url = directory.appendingPathComponent("\(utterance.id)-\(rate).wav")
                try synthesise(utterance, rate: rate, to: url)
                let audio = try AudioFileReader.read(contentsOf: url)
                let seconds = Double(audio.samples.count) / Double(audio.sampleRate)
                let heard = try await transcribed(audio, by: speech)
                let score = ShortUtteranceScore(
                    said: utterance, heard: heard?.text ?? "", detected: heard?.detectedLanguage?.code)
                byBucket[ShortUtteranceBucket(seconds: seconds), default: []].append(score)
                byKind["\(utterance.language.value)-\(utterance.kind.rawValue)", default: []].append(score)
                if verbose || !score.exact {
                    Terminal.clearLine()
                    print(
                        String(format: "  %.2fs %@ @%d: \"%@\" -> \"%@\"", seconds, utterance.id, rate,
                            utterance.text, heard?.text ?? ""))
                }
            }
        }
        Terminal.clearLine()
        print("\nBy clip length")
        table(byBucket.keys.sorted().map { ($0.rawValue, byBucket[$0] ?? []) })
        print("\nBy language and kind")
        table(byKind.keys.sorted().map { ($0, byKind[$0] ?? []) })
        print("\nAll")
        table([("all", byBucket.values.flatMap { $0 })])
    }

    private func synthesise(_ utterance: ShortUtterance, rate: Int, to url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let voice = utterance.language == .english ? englishVoice : hindiVoice
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-r", "\(rate)", "-o", url.path, "--data-format=LEF32@16000", utterance.text]
        try say.run()
        say.waitUntilExit()
        guard say.terminationStatus == 0 else { throw CleanExit.message("say failed for \(utterance.id).") }
    }

    /// What the speech path returns; `nil` when it finds no speech or refuses the clip as too short.
    private func transcribed(_ audio: AudioSamples, by speech: BackedSpeechEngine) async throws -> Transcription? {
        let result: Result<Transcription, SpeechEngineError>
        do {
            result = .success(try await speech.transcribe(audio, options: .init()))
        } catch {
            result = .failure(error)
        }
        switch result {
        case .success(let heard): return heard
        case .failure(.nothingHeard), .failure(.audioTooShort): return nil
        case .failure(let error): throw error
        }
    }

    private func table(_ rows: [(String, [ShortUtteranceScore])]) {
        print(
            "slice".padded(to: 20) + "clips".padded(to: 7) + "exact".padded(to: 9) + "invented".padded(to: 10)
                + "empty".padded(to: 9) + "wrong script/lang")
        for (label, scores) in rows {
            let rates = ShortUtteranceRates(scores)
            func cell(_ count: Int, _ width: Int) -> String {
                String(format: "%.0f%%", rates.percent(count)).padded(to: width)
            }
            print(
                label.padded(to: 20) + "\(rates.clips)".padded(to: 7) + cell(rates.exact, 9)
                    + cell(rates.invented, 10) + cell(rates.empty, 9) + cell(rates.wrongScriptOrLanguage, 0))
        }
    }
}
