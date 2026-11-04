// The `gap-distribution` command: each synthetic speaker's pause gaps, and break scores by rule.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval

/// Speaks the long-form corpus at several paces in several voices and reads the gaps back from the signal.
struct GapDistributionProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gap-distribution",
        abstract: "Measure each speaker's gaps on the long-form corpus and score fixed and rank pause rules."
    )

    @Option(name: .long, help: "Where the synthesised phrases are written.")
    var clipsPath = ".uttrflow-eval/gap-distribution-clips"

    @Option(name: .long, parsing: .upToNextOption, help: "Synthetic voices that read the corpus.")
    var voices = SpokenClips.voices

    @Option(name: .long, help: "Room noise mixed under every clip, in dBFS.")
    var roomDecibels = -60.0

    func run() async throws {
        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var speakers: [SpeakerGaps] = []
        for voice in voices {
            for profile in SpeakerProfile.paces(voice: voice) {
                var dictations: [[GapObservation]] = []
                for testCase in EvaluationCorpus.longForm {
                    let parts = RhythmClip.parts(of: testCase, for: profile)
                    let speech = try parts.map { try phrase($0.text, profile: profile, in: directory) }
                    guard let clip = RhythmClip.joined(parts, speech: speech, roomDecibels: roomDecibels)
                    else {
                        throw CleanExit.message("`say` produced no speech for \(testCase.id) in \(voice).")
                    }
                    dictations.append(clip.observations())
                }
                speakers.append(SpeakerGaps(profile: profile, dictations: dictations))
            }
        }
        print("Long-form corpus, room \(roomDecibels) dBFS, voices \(voices.joined(separator: ", "))\n")
        print(GapDistribution.distributionMarkdown(speakers))
        print("\nBreak F1 by rule and pace\n")
        print(GapDistribution.scoreMarkdown(speakers))
        let change = GapDistribution.change(speakers)
        print(
            String(
                format: "\nRank 3 spreads less fixed 700 ms, per dictation: %+.3f F1, paired 95%% bound %.3f",
                change.mean, change.bound))
    }

    private func phrase(_ text: String, profile: SpeakerProfile, in directory: URL) throws -> [Float] {
        let name = "\(profile.voice)-\(profile.rate ?? 0)-\(String(text.hashValueStable, radix: 16)).wav"
        let url = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            guard SaySynthesizer(rate: profile.rate).speak(text, voice: profile.voice, to: url) else {
                throw CleanExit.message("`say` could not speak \"\(text)\" in \(profile.voice).")
            }
        }
        return try AudioFileReader.read(contentsOf: url).samples
    }
}
