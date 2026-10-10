// The `input-level` command: word error rate against input gain and clipping, per language.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Replays every corpus recording at each level of the gain sweep and pools the word errors per level.
struct InputLevelProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "input-level",
        abstract: "Measure word errors when the input is quiet, at full scale, or clipped."
    )

    @Option(name: .long, help: "Where the recorded or synthesised corpus lives.")
    var corpusPath = TranscriptionCorpusStore.defaultDirectoryName

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, help: "Load the model from this folder instead of the model store.")
    var modelFolder: String?

    @Option(name: .long, help: "Where each model stage runs: shipping, gpu, neuralEngine, all or cpu.")
    var compute = SpeechComputePlan.shipping.rawValue

    func validate() throws {
        if SpeechComputePlan(rawValue: compute) == nil {
            throw ValidationError("Unknown compute plan '\(compute)'.")
        }
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
        guard modelFolder != nil || store.isInstalled(model) else {
            throw CleanExit.message("\(model.variant) is not installed. Run: uttrflow-dev models install")
        }
        let speech = SpeechEngineFactory.make(
            kind: .whisperKit, model: model,
            modelFolder: modelFolder.map { URL(fileURLWithPath: $0) } ?? store.location(of: model),
            compute: SpeechComputePlan(rawValue: compute) ?? .shipping)
        try await speech.prepare()

        let corpus = TranscriptionCorpusStore(directory: URL(fileURLWithPath: corpusPath))
        let recordings = try corpus.all(ordering: TranscriptionCorpus.all + TranscriptionCorpus.codeMixing)
        guard !recordings.isEmpty else {
            throw CleanExit.message("No recordings in \(corpusPath). Run: uttrflow-eval synthesise")
        }
        print("Probing \(counted(recordings.count, "recording")) with whisperKit \(model.variant)…")

        var byLanguage: [TranscriptionCase.Language: [[InputLevelOutcome]]] = [:]
        for (index, recording) in recordings.enumerated() {
            Terminal.show("\r  recording \(index + 1)/\(recordings.count)")
            let audio = try AudioFileReader.read(contentsOf: corpus.audioURL(for: recording.id))
            var outcomes: [InputLevelOutcome] = []
            for level in InputLevel.sweep {
                let samples = level.applied(to: audio.samples)
                guard let replay = AudioSamples(samples: samples, sampleRate: audio.sampleRate) else {
                    continue
                }
                let text = (try? await speech.transcribe(replay, options: .init()).text) ?? ""
                let score = TranscriptionScorer.score(text, against: recording.passage)
                guard let rate = score.wordErrorRate else { continue }
                let clipped =
                    CaptureQuality.measure(samples: samples, sampleRate: audio.sampleRate)?.clippedFraction
                    ?? 0
                outcomes.append(InputLevelOutcome(level: level, rate: rate, clippedFraction: clipped))
            }
            byLanguage[recording.passage.language, default: []].append(outcomes)
        }
        Terminal.clearLine()

        let reference = InputLevelTable.referenceLevel
        print("Change is pooled WER minus \(reference), a paired 95% bootstrap interval.")
        for language in TranscriptionCase.Language.allCases {
            guard let passages = byLanguage[language] else { continue }
            print("\n\(language.rawValue), \(counted(passages.count, "passage"))")
            print(
                "level".padded(to: 13) + "clipped".padded(to: 10) + "WER".padded(to: 9)
                    + "insertions".padded(to: 12) + "change")
            for row in InputLevelTable(passages: passages).rows {
                let change = row.change.map {
                    String(format: "%+.1f to %+.1f pts", $0.lowerBound * 100, $0.upperBound * 100)
                        + (row.isMeasurablyWorse ? ", worse" : "")
                }
                print(
                    row.level.description.padded(to: 13)
                        + String(format: "%.2f%%", row.meanClippedFraction * 100).padded(to: 10)
                        + String(format: "%.1f%%", row.wordErrorRate * 100).padded(to: 9)
                        + String(format: "%.1f%%", row.insertionRate * 100).padded(to: 12)
                        + (change ?? (row.level == reference ? "reference" : "-")))
            }
        }
    }
}
