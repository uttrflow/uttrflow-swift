// The `tail` command: how often a key released before the last word ends loses that word.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Releases synthetic clips before their speech ends and counts the last words the transcript loses.
struct TailProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tail",
        abstract: "Measure last-word loss when the key comes up before the speech ends."
    )

    @Option(name: .long, help: "Where the generated clips are written.")
    var clipsPath = ".uttrflow-eval/tail-clips"

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    /// For a model folder the store does not recognise as installed, such as one from an older revision.
    @Option(name: .long, help: "Load the model from this folder instead of the model store.")
    var modelFolder: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Milliseconds the speech runs on after the key-up.")
    var offsets: [Int] = [0, 100, 200, 300, 400]

    @Option(
        name: .long, parsing: .upToNextOption, help: "Tap sizes in frames; 0 is a stop that does not drain.")
    var taps: [Int] = [0, 1024, 2048, 4096]

    @Option(name: .long, help: "The device input rate the tap runs at.")
    var inputRate = 48_000.0

    @Option(name: .long, help: "How many evenly spaced block phases each cut is tried at.")
    var phases = 4

    func validate() throws {
        if phases < 1 { throw ValidationError("--phases must be at least 1.") }
        if offsets.contains(where: { $0 < 0 }) { throw ValidationError("--offsets must not be negative.") }
        if taps.contains(where: { $0 < 0 }) { throw ValidationError("--taps must not be negative.") }
        if inputRate <= 0 { throw ValidationError("--input-rate must be positive.") }
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

        let clips = try SpokenClips.generate(in: clipsPath, inputRate: inputRate)
        print(
            "Probing \(counted(clips.count, "clip")) with whisperKit \(model.variant) at \(Int(inputRate)) Hz…"
        )
        var control = 0
        var lost: [Int: [Int: Int]] = [:]
        var trials: [Int: [Int: Int]] = [:]
        for (index, clip) in clips.enumerated() {
            Terminal.show("\r  clip \(index + 1)/\(clips.count)")
            var heard: [Int: Bool] = [:]
            let keeps: (Int) async throws -> Bool = { length in
                if let known = heard[length] { return known }
                let text = try await speech.transcribe(
                    .canonical(Array(clip.samples[..<length])), options: .init()
                ).text
                let kept = TailCut.keptLastWord(
                    reference: clip.words, hypothesis: TextNormaliser.standard.words(text))
                heard[length] = kept
                return kept
            }
            if try await !keeps(clip.samples.count) { control += 1 }
            let end = TailCut.speechEnd(of: clip.samples)
            for offset in offsets {
                let cut = end - offset * AudioSamples.canonicalSampleRate / 1000
                for tap in taps {
                    let period = TailCut.tapSamples(tapFrames: tap, inputRate: inputRate)
                    for step in 0..<(period > 0 ? phases : 1) {
                        let kept = TailCut.kept(
                            clip.samples, cut: cut, tapSamples: period, phase: period * step / phases)
                        trials[tap, default: [:]][offset, default: 0] += 1
                        if try await !keeps(kept.count) { lost[tap, default: [:]][offset, default: 0] += 1 }
                    }
                }
            }
        }
        Terminal.clearLine()
        report(control: control, clips: clips.count, lost: lost, trials: trials)
    }

    private func report(control: Int, clips: Int, lost: [Int: [Int: Int]], trials: [Int: [Int: Int]]) {
        print("Last word lost with the whole clip: \(control) of \(clips)")
        print(
            "\n" + "tap frames".padded(to: 12) + "drain ms".padded(to: 10)
                + offsets.map { "+\($0) ms".padded(to: 10) }.joined())
        for tap in taps {
            let drain = tap == 0 ? "none" : String(format: "%.1f", Double(tap) / inputRate * 1000)
            let cells = offsets.map { offset -> String in
                let total = trials[tap]?[offset] ?? 0
                let count = lost[tap]?[offset] ?? 0
                let rate = total == 0 ? "n/a" : String(format: "%.1f%%", Double(count) / Double(total) * 100)
                return rate.padded(to: 10)
            }
            print((tap == 0 ? "undrained" : "\(tap)").padded(to: 12) + drain.padded(to: 10) + cells.joined())
        }
    }
}
