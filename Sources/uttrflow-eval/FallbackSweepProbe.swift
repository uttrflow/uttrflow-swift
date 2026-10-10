// The `fallback-sweep` command: what the decoder's temperature fallback buys in words, seconds and repeatability.
import ArgumentParser
private import Foundation
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Decodes the spoken clips under each fallback plan several times, and reports how often, how slow and how stable.
struct FallbackSweepProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fallback-sweep",
        abstract: "Sweep the decoder's fallback count and log-probability test against word error."
    )

    @Option(name: .long, help: "Where the generated clips are written.")
    var clipsPath = ".uttrflow-eval/tail-clips"

    @Option(name: .long, help: "Load the model from this folder instead of the model store.")
    var modelFolder: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Fallback counts swept at the shipping threshold.")
    var counts: [Int] = [5, 0, 1, 2]

    @Option(name: .long, parsing: .upToNextOption, help: "Log-probability thresholds at the shipping count.")
    var thresholds: [Float] = [-0.7, -1.3]

    @Option(name: .long, parsing: .upToNextOption, help: "Signal-to-noise ratios in dB; inf means clean.")
    var snrs: [Double] = [.infinity, 20, 10]

    @Option(name: .long, help: "Decodes of each clip under each plan.")
    var runs = 8

    @Option(name: .long, help: "Use only the first this many clips of each voice.")
    var perVoice = SpokenClips.sentences.count

    func validate() throws {
        if runs < 2 { throw ValidationError("--runs must be at least 2.") }
        if counts.contains(where: { $0 < 0 }) { throw ValidationError("--counts must not be negative.") }
        if perVoice < 1 { throw ValidationError("--per-voice must be at least 1.") }
    }

    func run() async throws {
        let model = SpeechModel.default
        let store = FileSystemSpeechModelStore.whisperKit()
        guard modelFolder != nil || store.isInstalled(model) else {
            throw CleanExit.message("\(model.variant) is not installed. Run: uttrflow-dev models install")
        }
        let folder = modelFolder.map { URL(fileURLWithPath: $0) } ?? store.location(of: model)
        let all = try SpokenClips.generate(in: clipsPath, inputRate: 48_000)
        let clips = all.enumerated().filter { $0.offset % SpokenClips.sentences.count < perVoice }
            .map(\.element)
        let plans =
            counts.map { SpeechFallbackPlan(temperatureCount: $0, logProbThreshold: -1.0) }
            + thresholds.map { SpeechFallbackPlan(temperatureCount: 5, logProbThreshold: $0) }
        print("whisperKit \(model.variant); \(clips.count) clips, \(runs) runs each")
        print("| Audio | Count | Log-prob | Fallback rate | Mean extra s | Worst extra s | Identical | WER |")
        print("|---|---|---|---|---|---|---|---|")
        for snr in snrs {
            let inputs = clips.map { snr.isInfinite ? $0.samples : WhiteNoise.added($0.samples, snr: snr) }
            for plan in plans {
                let speech = SpeechEngineFactory.make(
                    kind: .whisperKit, model: model, modelFolder: folder, fallback: plan)
                try await speech.prepare()
                var tally = FallbackSweep.Tally()
                for (clip, samples) in zip(clips, inputs) {
                    var texts: [[String]] = []
                    for _ in 0..<runs {
                        let heard = try await speech.transcribe(.canonical(samples), options: .init())
                        let words = TextNormaliser.standard.words(heard.text)
                        texts.append(words)
                        tally.add(
                            effort: heard.effort,
                            errors: WordErrorRate.measure(reference: clip.words, hypothesis: words).errors,
                            referenceWords: clip.words.count)
                    }
                    tally.addClip(identical: Set(texts).count == 1)
                }
                let audio = snr.isInfinite ? "clean" : "\(Int(snr)) dB"
                print(
                    "| \(audio) | \(plan.temperatureCount) | \(plan.logProbThreshold) | "
                        + tally.row + " |")
                await speech.release()
            }
        }
        print("Fallback rate: decodes with a warmer re-decode. Identical: clips whose \(runs) runs agree.")
    }
}

/// The sweep's sums and its deterministic noise.
private enum FallbackSweep {
    struct Tally {
        var decodes = 0
        var fellBack = 0
        var extraSeconds = 0.0
        var worstExtra = 0.0
        var clips = 0
        var identicalClips = 0
        var errors = 0
        var referenceWords = 0

        mutating func add(effort: DecodeEffort, errors: Int, referenceWords: Int) {
            decodes += 1
            if effort.fallbacks > 0 { fellBack += 1 }
            extraSeconds += effort.fallbackSeconds
            worstExtra = max(worstExtra, effort.fallbackSeconds)
            self.errors += errors
            self.referenceWords += referenceWords
        }

        mutating func addClip(identical: Bool) {
            clips += 1
            if identical { identicalClips += 1 }
        }

        var row: String {
            let percent: (Int, Int) -> String = { part, whole in
                String(format: "%.1f%%", whole == 0 ? 0 : 100 * Double(part) / Double(whole))
            }
            return [
                percent(fellBack, decodes),
                String(format: "%.3f", decodes == 0 ? 0 : extraSeconds / Double(decodes)),
                String(format: "%.2f", worstExtra),
                percent(identicalClips, clips),
                percent(errors, referenceWords),
            ].joined(separator: " | ")
        }
    }
}

/// White noise added at a fixed level, shared by the probes that measure noisy audio.
enum WhiteNoise {
    /// The samples with white noise at `snr` dB below their power, seeded so every run hears the same audio.
    static func added(_ samples: [Float], snr: Double) -> [Float] {
        Degradation.noise(.white, snr: snr).applied(
            to: samples, sampleRate: AudioSamples.canonicalSampleRate, seed: 0)
    }
}
