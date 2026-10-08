// The `announcement-bleed` command: whether a spoken announcement leaking into a recording becomes words.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Mixes a synthesised announcement into the head of synthetic clips and counts its words in the transcript.
struct AnnouncementBleedProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "announcement-bleed",
        abstract: "Measure the words a spoken announcement adds when it leaks into the head of a recording."
    )

    /// The lines spoken while the microphone could be open: the start, the cap warning, and a read-back.
    static let announcements = [
        "Listening.",
        "Dictation ends soon. 1 min left.",
        "Inserted: book a table for four on friday",
    ]

    @Option(name: .long, help: "Where the generated clips are written.")
    var clipsPath = ".uttrflow-eval/tail-clips"

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, help: "Load the model from this folder instead of the model store.")
    var modelFolder: String?

    @Option(name: .long, help: "The system voice that reads the announcements.")
    var voice = "Samantha"

    @Option(name: .long, parsing: .upToNextOption, help: "Peak levels of the leaked announcement, in dBFS.")
    var levels: [Double] = [-25.3, -20, -11.5, -8.8]

    @Option(name: .long, parsing: .upToNextOption, help: "Milliseconds of silence before the speech starts.")
    var leads: [Int] = [0, 700, 1200]

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

        let clips = try SpokenClips.generate(in: clipsPath, inputRate: inputRate)
        let heard: ([Float]) async throws -> [String] = { samples in
            let text = try await speech.transcribe(.canonical(samples), options: .init()).text
            return TextNormaliser.standard.words(text)
        }
        print("Probing \(counted(clips.count, "clip")) with whisperKit \(model.variant), voice \(voice)…")
        print("Per cell: announcement words in the transcript (clips with any), over \(clips.count) clips.")
        for (index, line) in Self.announcements.enumerated() {
            let spoken = try render(line, named: "announcement-\(index)")
            let words = Set(TextNormaliser.standard.words(line))
            print("\n\"\(line)\"")
            print(
                "lead ms".padded(to: 10)
                    + levels.map { String(format: "%.1f dBFS", $0).padded(to: 14) }.joined())
            for lead in leads {
                let leadSamples = lead * AudioSamples.canonicalSampleRate / 1000
                var leaked: [Double: Int] = [:]
                var clipsLeaking: [Double: Int] = [:]
                for (number, clip) in clips.enumerated() {
                    Terminal.show("\r  lead \(lead) ms, clip \(number + 1)/\(clips.count)")
                    let reference = Set(clip.words)
                    for level in levels {
                        let hypothesis = try await heard(
                            CueBleed.mixed(
                                speech: clip.samples, lead: leadSamples,
                                cue: CueBleed.scaled(spoken, toPeakDecibels: level)))
                        let added = hypothesis.filter { words.contains($0) && !reference.contains($0) }.count
                        leaked[level, default: 0] += added
                        if added > 0 { clipsLeaking[level, default: 0] += 1 }
                    }
                }
                Terminal.clearLine()
                let cells = levels.map { "\(leaked[$0] ?? 0) (\(clipsLeaking[$0] ?? 0))".padded(to: 14) }
                print("\(lead)".padded(to: 10) + cells.joined())
            }
        }
    }

    /// `line` read by `voice` as canonical samples, synthesised once and reused.
    private func render(_ line: String, named name: String) throws -> [Float] {
        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name)-\(voice).wav")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", url.path, "--data-format=LEF32@\(Int(inputRate))", line]
        try say.run()
        say.waitUntilExit()
        guard say.terminationStatus == 0 else { throw CleanExit.message("say failed for voice \(voice).") }
        return try AudioFileReader.read(contentsOf: url).samples
    }
}
