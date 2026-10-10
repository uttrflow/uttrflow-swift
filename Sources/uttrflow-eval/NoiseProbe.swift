// The `noise` command: word error rate per noise type and signal-to-noise ratio, per language.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Replays every corpus recording clean and under each noise of the sweep, and pools the word errors per condition.
struct NoiseProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "noise",
        abstract: "Measure word errors with white, pink, hum, babble or music noise added at stepped SNR."
    )

    @Option(name: .long, help: "Where the recorded or synthesised corpus lives.")
    var corpusPath = TranscriptionCorpusStore.defaultDirectoryName

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, help: "Load the model from this folder instead of the model store.")
    var modelFolder: String?

    @Option(name: .long, help: "Where each model stage runs: shipping, gpu, neuralEngine, all or cpu.")
    var compute = SpeechComputePlan.shipping.rawValue

    @Option(name: .long, help: "The run's seed; the same seed and corpus give the same noisy audio.")
    var seed: UInt64 = 0x5EED

    @Option(name: .long, help: "Compare every condition with a stored noise baseline at this path.")
    var baseline: String?

    @Flag(name: .long, help: "Write this run to --baseline as the new point of comparison.")
    var saveBaseline = false

    @Flag(name: .long, help: "Exit non-zero when any condition or slice has got worse. For CI.")
    var failOnRegression = false

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
        print(
            "Probing \(counted(recordings.count, "recording")) with whisperKit \(model.variant), seed \(seed)…"
        )

        var byLanguage: [TranscriptionCase.Language: [[ConditionTable<Degradation>.Outcome]]] = [:]
        var entries: [BaselineEntry] = []
        for (index, recording) in recordings.enumerated() {
            Terminal.show("\r  recording \(index + 1)/\(recordings.count)")
            let audio = try AudioFileReader.read(contentsOf: corpus.audioURL(for: recording.id))
            let recordingSeed = Degradation.seed(for: recording.id, run: seed)
            var outcomes: [ConditionTable<Degradation>.Outcome] = []
            for condition in Degradation.noiseSweep {
                let samples = condition.applied(
                    to: audio.samples, sampleRate: audio.sampleRate, seed: recordingSeed)
                guard let replay = AudioSamples(samples: samples, sampleRate: audio.sampleRate) else {
                    continue
                }
                let text = (try? await speech.transcribe(replay, options: .init()).text) ?? ""
                let score = TranscriptionScorer.score(
                    text, against: recording.passage, cohortID: recording.cohort?.id,
                    recordingIdentity: recording.recordingIdentity, recordID: recording.recordID)
                let named = condition == .clean ? nil : condition.description
                entries.append(BaselineEntry(score, condition: named))
                guard let rate = score.wordErrorRate else { continue }
                outcomes.append(.init(condition: condition, rate: rate))
            }
            byLanguage[recording.passage.language, default: []].append(outcomes)
        }
        Terminal.clearLine()

        print(
            "Change is pooled WER minus clean, a paired 95% bootstrap interval. Conditions are never pooled.")
        for language in TranscriptionCase.Language.allCases {
            guard let passages = byLanguage[language] else { continue }
            let table = ConditionTable(passages: passages, reference: Degradation.clean)
            print("\n\(language.rawValue), \(counted(passages.count, "passage"))")
            print("condition".padded(to: 16) + "WER".padded(to: 9) + "insertions".padded(to: 12) + "change")
            for row in table.rows {
                let change = row.change.map {
                    String(format: "%+.1f to %+.1f pts", $0.lowerBound * 100, $0.upperBound * 100)
                        + (row.isMeasurablyWorse ? ", worse" : "")
                }
                print(
                    row.condition.description.padded(to: 16)
                        + String(format: "%.1f%%", row.wordErrorRate * 100).padded(to: 9)
                        + String(format: "%.1f%%", row.insertionRate * 100).padded(to: 12)
                        + (change ?? (row.condition == .clean ? "reference" : "-")))
            }
            guard let clean = table.referenceRow?.wordErrorRate else { continue }
            let margin = Int(NoiseBreakpoint.margin * 100)
            let falls = NoiseBreakpoint.first(in: table.rows, clean: clean).map { kind, snr in
                "\(kind.rawValue) " + (snr.map { "\(Int($0)) dB" } ?? "none")
            }
            print("First SNR more than \(margin) pts above clean: " + falls.joined(separator: ", "))
        }

        guard let baseline else { return }
        try BaselineGate(path: baseline, saveBaseline: saveBaseline, failOnRegression: failOnRegression)
            .judge(
                AccuracyBaseline(
                    label: "noise whisperKit \(model.variant), \(compute), seed \(seed)",
                    recogniser: model.recogniserPins, recordedAt: Date(),
                    normalisation: TextNormaliser.standard.rules, entries: entries))
    }
}
