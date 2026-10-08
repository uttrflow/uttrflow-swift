// The `silence-stop` command: how often ending on silence would stop a long-form dictation mid-speech.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval

/// Speaks the long-form corpus, then checks it as a live recording is checked, for each wait a person can choose.
struct SilenceStopProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "silence-stop",
        abstract: "Measure false stops and stop delay for each end-on-silence wait on the long-form corpus."
    )

    @Option(name: .long, help: "Where the synthesised long-form clips are written.")
    var clipsPath = ".uttrflow-eval/long-form-clips"

    @Option(name: .long, help: "Room noise mixed under every clip, in dBFS.")
    var roomDecibels = -60.0

    @Option(name: .long, help: "Voice for `say`; the system voice when absent.")
    var voice: String?

    func run() async throws {
        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stops = SilenceStop.choices.compactMap(SilenceStop.init(seconds:))
        let tail = (stops.map(\.wait).max() ?? .zero) + .seconds(2)
        var rows = stops.map { SilenceStopRow(stop: $0) }
        for testCase in EvaluationCorpus.longForm {
            let clip = directory.appendingPathComponent("\(testCase.id).wav")
            if !FileManager.default.fileExists(atPath: clip.path) {
                guard SaySynthesizer().speak(LongFormRecipe(testCase).script, voice: voice, to: clip) else {
                    throw CleanExit.message("`say` could not speak \(testCase.id).")
                }
            }
            let spoken = try AudioFileReader.read(contentsOf: clip).samples
            let rate = AudioSamples.canonicalSampleRate
            let samples = withRoom(spoken + [Float](repeating: 0, count: Int(tail / .seconds(1)) * rate))
            for index in rows.indices { rows[index].check(samples, speechEnds: spoken.count, rate: rate) }
        }
        let clips = counted(EvaluationCorpus.longForm.count, "clip")
        print("Long-form corpus: \(clips), room at \(roomDecibels) dBFS")
        print("| Wait | False stops | Longest quiet mid-speech s | Stop delay after the last word s |")
        print("|---|---|---|---|")
        for row in rows { print(row.line) }
    }

    /// The clip with seeded room noise under it, so a pause is a quiet room and not digital zeros.
    private func withRoom(_ samples: [Float]) -> [Float] {
        let level = Float(pow(10, roomDecibels / 20)) * 3.46
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        return samples.map { sample in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return sample + (Float(state >> 40) / Float(1 << 24) - 0.5) * level
        }
    }
}

/// One wait's results, gathered by checking each clip every poll the way the pipeline does.
private struct SilenceStopRow {
    let stop: SilenceStop
    var falseStops = 0
    var longestQuiet = 0.0
    var delays: [Double] = []

    /// Reads the clip as the live check reads it: from the last read less the look-back, every poll.
    mutating func check(_ samples: [Float], speechEnds: Int, rate: Int) {
        let step = Int(SilenceStop.poll / .seconds(1) * Double(rate))
        var heard = 0
        for end in stride(from: step, through: samples.count, by: step) {
            let window = Array(samples[Swift.max(0, heard - stop.lookBack(atRate: rate))..<end])
            heard = end
            if end < speechEnds, let quiet = VoiceActivity.trailingSilence(in: window, sampleRate: rate) {
                longestQuiet = Swift.max(longestQuiet, quiet / .seconds(1))
            }
            guard stop.isReached(in: window, sampleRate: rate) else { continue }
            if end < speechEnds {
                falseStops += 1
            } else {
                delays.append(Double(end - speechEnds) / Double(rate))
            }
            return
        }
    }

    var line: String {
        let delay =
            delays.isEmpty ? "none" : String(format: "%.1f to %.1f", delays.min() ?? 0, delays.max() ?? 0)
        let quiet = String(format: "%.2f", longestQuiet)
        return "| \(Int(stop.wait / .seconds(1))) s | \(falseStops) | \(quiet) | \(delay) |"
    }
}
