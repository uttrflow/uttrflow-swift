// The `pace` command: word errors, piece cuts and the loop check per speaking rate and pitch shift.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Replays every corpus recording at stepped speaking rates and pitches and measures what depends on pace.
struct PaceProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pace",
        abstract: "Measure word errors, piece cuts and the loop check at stepped speaking rate and pitch."
    )

    @Option(name: .long, help: "Where the recorded or synthesised corpus lives.")
    var corpusPath = TranscriptionCorpusStore.defaultDirectoryName

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, help: "Load the model from this folder instead of the model store.")
    var modelFolder: String?

    @Option(name: .long, help: "Where each model stage runs: shipping, gpu, neuralEngine, all or cpu.")
    var compute = SpeechComputePlan.shipping.rawValue

    @Flag(name: .long, help: "Count cuts and loop-check hits only; load no model and report no word errors.")
    var structureOnly = false

    func validate() throws {
        if SpeechComputePlan(rawValue: compute) == nil {
            throw ValidationError("Unknown compute plan '\(compute)'.")
        }
    }

    /// Pooled counts for one variant.
    private struct Tally {
        var pieces = 0
        var early = 0
        var midWord = 0
        var timed = 0
        var loopCuts = 0
        var eligible = 0
        var aboveLimit = 0
        var recordings = 0
    }

    func run() async throws {
        var speech: (any SpeechEngine)?
        var modelName = "none"
        if !structureOnly {
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
            let engine = SpeechEngineFactory.make(
                kind: .whisperKit, model: model,
                modelFolder: modelFolder.map { URL(fileURLWithPath: $0) } ?? store.location(of: model),
                compute: SpeechComputePlan(rawValue: compute) ?? .shipping)
            try await engine.prepare()
            speech = engine
            modelName = model.variant
        }

        let corpus = TranscriptionCorpusStore(directory: URL(fileURLWithPath: corpusPath))
        let recordings = try corpus.all(ordering: TranscriptionCorpus.all + TranscriptionCorpus.codeMixing)
        guard !recordings.isEmpty else {
            throw CleanExit.message("No recordings in \(corpusPath). Run: uttrflow-eval synthesise")
        }
        print("Probing \(counted(recordings.count, "recording")) with model \(modelName)…")

        var byLanguage: [TranscriptionCase.Language: [[ConditionTable<SpeechVariant>.Outcome]]] = [:]
        var tallies: [String: Tally] = [:]
        let speechAvailable = speech != nil
        for (index, recording) in recordings.enumerated() {
            Terminal.show("\r  recording \(index + 1)/\(recordings.count)")
            let audio = try AudioFileReader.read(contentsOf: corpus.audioURL(for: recording.id))
            let words = recording.passage.romanised.split(whereSeparator: \.isWhitespace).count
            var outcomes: [ConditionTable<SpeechVariant>.Outcome] = []
            for variant in SpeechVariant.sweep {
                let samples = variant.applied(to: audio.samples, sampleRate: audio.sampleRate)
                let structure = PaceStructure(samples: samples, sampleRate: audio.sampleRate)
                var tally = tallies[variant.description, default: Tally()]
                tally.recordings += 1
                tally.pieces += structure.pieces
                tally.early += structure.earlyCuts
                // A sentence really said twice at this pace: the loop check must keep both copies.
                if words >= RecognitionLoop.fewestCopyWords, structure.speechSeconds > 0 {
                    tally.eligible += 1
                    if Double(words) / structure.speechSeconds > RecognitionLoop.fastestSpeech {
                        tally.aboveLimit += 1
                    }
                    let twice = recording.passage.romanised + " " + recording.passage.romanised
                    let kept = RecognitionLoop.undone(
                        Transcription(text: twice), speechDuration: .seconds(2 * structure.speechSeconds))
                    if kept.text.split(whereSeparator: \.isWhitespace).count < 2 * words {
                        tally.loopCuts += 1
                    }
                }
                guard let speech, let replay = AudioSamples(samples: samples, sampleRate: audio.sampleRate)
                else {
                    tallies[variant.description] = tally
                    continue
                }
                let heard = try? await speech.transcribe(replay, options: .init())
                let spans = (heard?.segments ?? []).flatMap(\.words).compactMap { word in
                    word.start.flatMap { start in
                        word.end.flatMap { end in
                            start <= end ? start.inSeconds...end.inSeconds : nil
                        }
                    }
                }
                if !spans.isEmpty {
                    tally.timed += structure.cuts.count
                    tally.midWord += structure.cutsInsideWords(spans)
                }
                tallies[variant.description] = tally
                let score = TranscriptionScorer.score(
                    heard?.text ?? "", against: recording.passage, cohortID: recording.cohort?.id,
                    recordingIdentity: recording.recordingIdentity, recordID: recording.recordID)
                guard let rate = score.wordErrorRate else { continue }
                outcomes.append(.init(condition: variant, rate: rate))
            }
            if !outcomes.isEmpty { byLanguage[recording.passage.language, default: []].append(outcomes) }
        }
        Terminal.clearLine()

        for language in TranscriptionCase.Language.allCases {
            guard let passages = byLanguage[language] else { continue }
            let table = ConditionTable(passages: passages, reference: SpeechVariant.original)
            print("\n\(language.rawValue), \(counted(passages.count, "passage"))")
            print("condition".padded(to: 12) + "WER".padded(to: 9) + "insertions".padded(to: 12) + "change")
            for row in table.rows {
                let change = row.change.map {
                    String(format: "%+.1f to %+.1f pts", $0.lowerBound * 100, $0.upperBound * 100)
                        + (row.isMeasurablyWorse ? ", worse" : "")
                }
                print(
                    row.condition.description.padded(to: 12)
                        + String(format: "%.1f%%", row.wordErrorRate * 100).padded(to: 9)
                        + String(format: "%.1f%%", row.insertionRate * 100).padded(to: 12)
                        + (change ?? (row.condition == .original ? "reference" : "-")))
            }
        }

        print("\nPiece cuts and the loop check, pooled over every recording")
        print(
            "condition".padded(to: 12) + "pieces".padded(to: 8) + "early".padded(to: 8)
                + "mid-word".padded(to: 10) + "said-twice cut".padded(to: 16) + "over 4.8 w/s")
        for variant in SpeechVariant.sweep {
            guard let tally = tallies[variant.description] else { continue }
            print(
                variant.description.padded(to: 12) + "\(tally.pieces)".padded(to: 8)
                    + "\(tally.early)".padded(to: 8)
                    + (speechAvailable ? "\(tally.midWord)/\(tally.timed)" : "-").padded(to: 10)
                    + "\(tally.loopCuts)/\(tally.eligible)".padded(to: 16)
                    + "\(tally.aboveLimit)/\(tally.eligible)")
        }
    }
}
