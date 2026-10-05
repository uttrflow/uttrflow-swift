// The `cue-bleed` command: whether the start cue leaking into a recording costs words.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Mixes the shipping start cue into the head of synthetic clips and counts the words it changes.
struct CueBleedProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cue-bleed",
        abstract: "Measure word errors when the start cue leaks into the head of a recording."
    )

    @Option(name: .long, help: "Where the generated clips are written.")
    var clipsPath = ".uttrflow-eval/tail-clips"

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, help: "Load the model from this folder instead of the model store.")
    var modelFolder: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Peak levels of the leaked cue, in dBFS.")
    var levels: [Double] = [-25.3, -20, -14.2, -11.5, -8.8]

    @Option(name: .long, parsing: .upToNextOption, help: "Milliseconds of silence before the speech starts.")
    var leads: [Int] = [0, 300, 700, 1200]

    @Option(name: .long, help: "The rate the clips are synthesised at.")
    var inputRate = 48_000.0

    func validate() throws {
        if leads.contains(where: { $0 < 0 }) { throw ValidationError("--leads must not be negative.") }
        if levels.contains(where: { $0 > 0 }) {
            throw ValidationError("--levels must be at or under 0 dBFS.")
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
            modelFolder: modelFolder.map { URL(fileURLWithPath: $0) } ?? store.location(of: model))
        try await speech.prepare()

        let cue = CueSound.start
        guard let file = SystemSoundFile.load(cue.sound) else {
            throw CleanExit.message("The start cue's system sound \(cue.sound.name) is missing.")
        }
        let rate = Double(AudioSamples.canonicalSampleRate)
        let shaped = CueShaping.shape(file.samples, sourceRate: file.sampleRate, cue: cue, outputRate: rate)
        print(
            "Start cue \(cue.sound.name) at \(cue.semitones) semitones, low-pass \(Int(cue.lowPassHz)) Hz:"
                + String(
                    format: " %.2f s, source peak %.1f dBFS", Double(shaped.count) / rate,
                    CueBleed.peakDecibels(of: shaped)))

        let clips = try SpokenClips.generate(in: clipsPath, inputRate: inputRate)
        print("Probing \(counted(clips.count, "clip")) with whisperKit \(model.variant)…")
        let words = clips.reduce(0) { $0 + $1.words.count }
        var clean: [Int: Int] = [:]
        var errors: [Int: [Double: Int]] = [:]
        var changed: [Int: [Double: Int]] = [:]
        for (index, clip) in clips.enumerated() {
            Terminal.show("\r  clip \(index + 1)/\(clips.count)")
            for lead in leads {
                let leadSamples = lead * AudioSamples.canonicalSampleRate / 1000
                let heard: ([Float]) async throws -> [String] = { samples in
                    let text = try await speech.transcribe(.canonical(samples), options: .init()).text
                    return TextNormaliser.standard.words(text)
                }
                let baseline = try await heard(
                    CueBleed.mixed(speech: clip.samples, lead: leadSamples, cue: []))
                clean[lead, default: 0] +=
                    WordErrorRate.measure(reference: clip.words, hypothesis: baseline).errors
                for level in levels {
                    let mixed = CueBleed.mixed(
                        speech: clip.samples, lead: leadSamples,
                        cue: CueBleed.scaled(shaped, toPeakDecibels: level))
                    let hypothesis = try await heard(mixed)
                    errors[lead, default: [:]][level, default: 0] +=
                        WordErrorRate.measure(reference: clip.words, hypothesis: hypothesis).errors
                    if hypothesis != baseline { changed[lead, default: [:]][level, default: 0] += 1 }
                }
            }
        }
        Terminal.clearLine()
        print(
            "Word edits over \(words) reference words per cell; in brackets, clips whose words differ from no cue."
        )
        print(
            "\n" + "lead ms".padded(to: 10) + "no cue".padded(to: 10)
                + levels.map { String(format: "%.1f dBFS", $0).padded(to: 14) }.joined())
        for lead in leads {
            let cells = levels.map { level in
                "\(errors[lead]?[level] ?? 0) (\(changed[lead]?[level] ?? 0))".padded(to: 14)
            }
            print("\(lead)".padded(to: 10) + "\(clean[lead] ?? 0)".padded(to: 10) + cells.joined())
        }
    }
}
