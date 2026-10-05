// The `nonspeech` command: how often sound with no words in it, or a pause after speech, becomes typed text.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Runs the non-speech corpus through the shipping speech path and gates its insertion and loop rates.
struct NonSpeechProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nonspeech",
        abstract: "Measure text invented from silence and noise, and phrases looped, then gate both rates."
    )

    @Option(name: .long, help: "Where the synthesised speech clips are written.")
    var clipsPath = ".uttrflow-eval/tail-clips"

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, help: "Load the model from this folder instead of the model store.")
    var modelFolder: String?

    @Option(name: .long, help: "Generated clips of each non-speech kind, each from its own seed.")
    var seeds = 3

    @Option(name: .long, help: "Seconds of each non-speech kind appended after a spoken sentence.")
    var tailSeconds = 4.0

    @Option(name: .long, help: "The highest insertion rate that passes, from 0 to 1.")
    var maxInsertionRate = 0.0

    @Option(name: .long, help: "The highest repetition-loop rate that passes, from 0 to 1.")
    var maxLoopRate = 0.0

    @Option(name: .long, help: "Dictionary words to condition the recogniser on, comma separated.")
    var vocabulary = ""

    @Option(name: .long, help: "The highest prompt-echo rate that passes, from 0 to 1.")
    var maxEchoRate = 0.0

    func validate() throws {
        if seeds < 1 { throw ValidationError("--seeds must be at least 1.") }
        if tailSeconds < 0 { throw ValidationError("--tail-seconds must not be negative.") }
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
            modelFolder: modelFolder.map { URL(fileURLWithPath: $0) } ?? store.location(of: model))
        try await speech.prepare()

        let words = vocabulary.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let prompt =
            words.isEmpty
            ? []
            : TextNormaliser.standard.words(VocabularyPrompt.opening + " " + words.joined(separator: " "))
        let cases = try corpus()
        print("Probing \(counted(cases.count, "clip")) with whisperKit \(model.variant)…")
        var byKind: [String: [NonSpeechScore]] = [:]
        for (index, clip) in cases.enumerated() {
            Terminal.show("\r  clip \(index + 1)/\(cases.count)")
            let text = try await typed(clip.samples, vocabulary: words, by: speech)
            let score = NonSpeechScore(
                reference: clip.words, hypothesis: TextNormaliser.standard.words(text), prompt: prompt)
            byKind[clip.kind, default: []].append(score)
            if score.insertedWords > 0 || score.looped {
                Terminal.clearLine()
                print("  \(clip.kind): \"\(text)\"")
            }
        }
        Terminal.clearLine()
        try report(byKind)
    }

    /// What dictation would type for `samples`: nothing when the speech path finds no speech.
    private func typed(
        _ samples: [Float], vocabulary: [String], by speech: BackedSpeechEngine
    ) async throws -> String {
        let result: Result<Transcription, SpeechEngineError>
        do {
            result = .success(
                try await speech.transcribe(.canonical(samples), options: .init(vocabulary: vocabulary)))
        } catch {
            result = .failure(error)
        }
        switch result {
        case .success(let heard): return heard.text
        case .failure(.nothingHeard): return ""
        case .failure(let error): throw error
        }
    }

    private struct Clip {
        let kind: String
        let samples: [Float]
        let words: [String]
    }

    /// Every kind alone, once per seed, then every kind after each spoken sentence in one voice.
    private func corpus() throws -> [Clip] {
        var clips: [Clip] = []
        for kind in NonSpeechKind.allCases {
            for seed in 0..<seeds {
                clips.append(Clip(kind: kind.rawValue, samples: kind.samples(seed: UInt64(seed)), words: []))
            }
        }
        let spoken = try SpokenClips.generate(
            in: clipsPath, inputRate: Double(AudioSamples.canonicalSampleRate))
        for (index, sentence) in spoken.prefix(SpokenClips.sentences.count).enumerated() {
            for kind in NonSpeechKind.allCases {
                let tail = kind.samples(seconds: tailSeconds, seed: UInt64(index))
                clips.append(
                    Clip(
                        kind: "speech+\(kind.rawValue)", samples: sentence.samples + tail,
                        words: sentence.words))
            }
        }
        return clips
    }

    private func report(_ byKind: [String: [NonSpeechScore]]) throws {
        print(
            "kind".padded(to: 20) + "clips".padded(to: 8) + "inserted".padded(to: 10) + "looped".padded(to: 8)
                + "echoed")
        for kind in byKind.keys.sorted() {
            let rates = NonSpeechRates(byKind[kind] ?? [])
            print(
                kind.padded(to: 20) + "\(rates.clips)".padded(to: 8) + "\(rates.inserted)".padded(to: 10)
                    + "\(rates.looped)".padded(to: 8) + "\(rates.echoed)")
        }
        let total = NonSpeechRates(byKind.values.flatMap { $0 })
        print(
            String(
                format: "\nInsertion rate %.1f%% (%d of %d)", total.insertionRate * 100, total.inserted,
                total.clips))
        print(
            String(
                format: "Repetition-loop rate %.1f%% (%d of %d)", total.loopRate * 100, total.looped,
                total.clips))
        print(
            String(
                format: "Prompt-echo rate %.1f%% (%d of %d)", total.echoRate * 100, total.echoed, total.clips)
        )
        let failures = total.exceeded(
            insertionCeiling: maxInsertionRate, loopCeiling: maxLoopRate, echoCeiling: maxEchoRate)
        guard failures.isEmpty else {
            print("Above its ceiling: \(failures.joined(separator: ", ")).")
            throw ExitCode.failure
        }
    }
}
