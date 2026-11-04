// The `pause-timing` command: how far the recogniser's word times can be trusted as evidence of a pause.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Builds clips with pauses of known length and compares the word-time gap with the length built in.
struct PauseTimingProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pause-timing",
        abstract: "Compare word-time gaps with pauses of known length, by pause length and by word type."
    )

    @Option(name: .long, help: "Where the synthesised phrases are written.")
    var clipsPath = ".uttrflow-eval/pause-timing-clips"

    @Option(name: .long, parsing: .upToNextOption, help: "Pauses built between the phrases, in milliseconds.")
    var pauses = [0, 150, 300, 600, 1000]

    @Option(name: .long, parsing: .upToNextOption, help: "Synthetic voices that read the phrases.")
    var voices = SpokenClips.voices

    @Option(name: .long, help: "Room noise mixed under every clip, in dBFS.")
    var roomDecibels = -60.0

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    /// A phrase pair: the words before the pause and the words after it, with the kind of word the pause follows.
    private struct Pair {
        let kind: String
        let first: String
        let second: String
    }

    private static let pairs: [Pair] = [
        Pair(kind: "content word", first: "please move the blue folder", second: "onto the shelf"),
        Pair(kind: "content word", first: "we can meet near the bakery", second: "after lunch"),
        Pair(kind: "content word", first: "the train to the coast", second: "leaves soon"),
        Pair(kind: "function word", first: "please move the blue folder onto the", second: "shelf"),
        Pair(kind: "function word", first: "we can meet near the bakery after", second: "lunch"),
        Pair(kind: "function word", first: "remind me to water the", second: "plants tomorrow"),
        Pair(kind: "filler", first: "please move the blue folder um", second: "onto the shelf"),
        Pair(kind: "filler", first: "we can meet uh", second: "near the bakery"),
        Pair(kind: "filler", first: "remind me to um", second: "water the plants"),
        Pair(kind: "before a number", first: "please move", second: "seven blue folders"),
        Pair(kind: "before a number", first: "the train leaves at", second: "twelve today"),
        Pair(kind: "before a number", first: "send the draft to", second: "three people"),
    ]

    func validate() throws {
        if pauses.contains(where: { $0 < 0 }) { throw ValidationError("--pauses must not be negative.") }
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

        var trials: [PauseTiming.Trial] = []
        var skipped = 0
        for voice in voices {
            for (index, pair) in Self.pairs.enumerated() {
                let first = try phrase(pair.first, voice: voice, in: directory)
                let second = try phrase(pair.second, voice: voice, in: directory)
                let expected =
                    pair.first.split(separator: " ").count + pair.second.split(separator: " ").count
                for pause in pauses {
                    guard
                        let clip = PauseTiming.joined(
                            first, second, gapMilliseconds: pause, roomDecibels: roomDecibels)
                    else {
                        throw CleanExit.message("`say` produced no speech for pair \(index) in \(voice).")
                    }
                    let heard = try await speech.transcribe(.canonical(clip.samples), options: .init())
                    let words = heard.segments.flatMap(\.words)
                    guard words.count == expected else {
                        skipped += 1
                        continue
                    }
                    let boundary = pair.first.split(separator: " ").count - 1
                    trials.append(
                        PauseTiming.Trial(
                            kind: pair.kind, truth: pause,
                            wordGap: PauseTiming.wordGapMilliseconds(after: boundary, in: words),
                            audioGap: PauseTiming.voiceActivityGapMilliseconds(in: clip)))
                }
            }
        }
        print("Model \(model.variant), room \(roomDecibels) dBFS, voices \(voices.joined(separator: ", "))\n")
        print(PauseTiming.markdown(trials, skipped: skipped))
        let trusted = PauseTiming.trustedMinimum(trials, tolerance: 100, shown: 300, reliability: 0.9)
        print("\nTrusted minimum pause in the word times: \(trusted.map { "\($0) ms" } ?? "none")")
    }

    /// The phrase read by `voice`, synthesised once and reused.
    private func phrase(_ text: String, voice: String, in directory: URL) throws -> [Float] {
        let url = directory.appendingPathComponent("\(voice)-\(String(text.hashValueStable, radix: 16)).wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            guard SaySynthesizer().speak(text, voice: voice, to: url) else {
                throw CleanExit.message("`say` could not speak \"\(text)\" in \(voice).")
            }
        }
        return try AudioFileReader.read(contentsOf: url).samples
    }
}
