// The `retry-parity` command: whether retrying a kept recording gives the words the live dictation gave.
import ArgumentParser
private import Foundation
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Decodes synthetic dictations as the live path cuts them and as a retry reads them back, and compares the words.
struct RetryParityProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "retry-parity",
        abstract: "Compare a live dictation's words with a retry of its kept 16-bit recording."
    )

    @Option(name: .long, help: "Where the generated clips are written.")
    var clipsPath = ".uttrflow-eval/tail-clips"

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, help: "Load the model from this folder instead of the model store.")
    var modelFolder: String?

    @Option(
        name: .long, parsing: .upToNextOption, help: "Silences between sentences, in milliseconds, cycled.")
    var gaps: [Int] = [1200, 350, 900, 250]

    @Option(name: .long, parsing: .upToNextOption, help: "Levels the passages are played at, in dB.")
    var gains: [Double] = [0, -30]

    @Option(name: .long, help: "Seconds between the live path's looks for a cut.")
    var poll = 1.0

    func validate() throws {
        if gaps.isEmpty || gaps.contains(where: { $0 < 0 }) {
            throw ValidationError("--gaps must hold non-negative values.")
        }
        if poll <= 0 { throw ValidationError("--poll must be positive.") }
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

        let clips = try SpokenClips.generate(in: clipsPath, inputRate: 48_000)
        let rate = AudioSamples.canonicalSampleRate
        let perVoice = SpokenClips.sentences.count
        print(
            "whisperKit \(model.variant); passages of \(perVoice) sentences, gaps \(gaps) ms, poll \(poll) s")
        let columns = ["live", "retry-f32", "retry-16", "whole-f32", "whole-16"].map { $0.padded(to: 12) }
        print("case".padded(to: 18) + "secs".padded(to: 6) + columns.joined() + "16-bit changes")
        for (voiceIndex, voice) in SpokenClips.voices.enumerated() {
            let mine = clips[(voiceIndex * perVoice)..<((voiceIndex + 1) * perVoice)]
            var passage: [Float] = []
            var reference: [String] = []
            for (index, clip) in mine.enumerated() {
                passage += clip.samples
                reference += clip.words
                passage += [Float](repeating: 0, count: gaps[index % gaps.count] * rate / 1000)
            }
            for gain in gains {
                let scale = Float(pow(10, gain / 20))
                let float = passage.map { $0 * scale }
                let stored = RetryParity.roundTripped(float)
                let decode: ([Float], [Range<Int>]) async throws -> ([String], [[String]]) = {
                    samples, pieces in
                    var each: [[String]] = []
                    for piece in pieces {
                        let text = try await speech.transcribe(
                            .canonical(Array(samples[piece])), options: .init()
                        ).text
                        each.append(TextNormaliser.standard.words(text))
                    }
                    return (each.flatMap(\.self), each)
                }
                let livePieces = RetryParity.livePieces(
                    float, sampleRate: rate, pollSamples: Int(poll * Double(rate)))
                let retryPieces = RetryParity.retryPieces(float, sampleRate: rate)
                let storedPieces = RetryParity.retryPieces(stored, sampleRate: rate)
                let live = try await decode(float, livePieces)
                let retryFloat = try await decode(float, retryPieces)
                let retryStored = try await decode(stored, storedPieces)
                let wholeFloat = try await decode(float, [float.indices])
                let wholeStored = try await decode(stored, [stored.indices])
                let cell: ([String], Int) -> String = { words, count in
                    let errors = WordErrorRate.measure(reference: reference, hypothesis: words).errors
                    return "\(errors)/\(count)p".padded(to: 12)
                }
                let label = "\(voice) \(Int(gain)) dB"
                let seconds = String(format: "%.1f", Double(float.count) / Double(rate))
                let cells: [String] = [
                    cell(live.0, livePieces.count), cell(retryFloat.0, retryPieces.count),
                    cell(retryStored.0, storedPieces.count), cell(wholeFloat.0, 1), cell(wholeStored.0, 1),
                ]
                let rounding = wholeFloat.0 != wholeStored.0 || retryFloat.0 != retryStored.0
                let moved = storedPieces == retryPieces ? "" : " (cuts moved)"
                let row: String = label.padded(to: 18) + seconds.padded(to: 6) + cells.joined()
                print(row + (rounding ? "yes" : "no") + moved)
                if live.0 != retryStored.0 {
                    let shown: ([[String]]) -> String = { pieces in
                        pieces.map { $0.joined(separator: " ") }.joined(separator: " | ")
                    }
                    print("    live:  \(shown(live.1))")
                    print("    retry: \(shown(retryStored.1))")
                }
            }
        }
        let sentences = SpokenClips.sentences.count
        print("Cells: word edits against \(sentences) reference sentences / pieces decoded.")
    }
}
