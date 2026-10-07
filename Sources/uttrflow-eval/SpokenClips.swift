// Invented sentences spoken by `say`, the clips the tail and cue-bleed probes share.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowEval

/// One synthesised sentence as canonical samples, with the words it reads.
struct SpokenClip {
    let samples: [Float]
    let words: [String]
}

/// Synthesises each sentence in each voice once, and reuses the files on later runs.
enum SpokenClips {
    /// Invented sentences whose last words end on a stop, a fricative, a nasal and a vowel.
    static let sentences = [
        "please move the blue folder onto the shelf",
        "we can meet near the bakery after lunch",
        "the train to the coast leaves at seven",
        "put the spare keys under the green mat",
        "remind me to water the plants tomorrow",
        "the printer on the second floor is jammed",
        "send the draft to the whole team",
        "our new kettle makes a strange noise",
    ]

    static let voices = ["Samantha", "Daniel", "Karen", "Rishi"]

    /// Every voice reading every sentence, written to `path` at `inputRate` and read back as canonical samples.
    static func generate(in path: String, inputRate: Double) throws -> [SpokenClip] {
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var clips: [SpokenClip] = []
        for voice in voices {
            for (index, sentence) in sentences.enumerated() {
                let url = directory.appendingPathComponent("\(voice)-\(index).wav")
                if !FileManager.default.fileExists(atPath: url.path) {
                    let say = Process()
                    say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                    say.arguments = [
                        "-v", voice, "-o", url.path, "--data-format=LEF32@\(Int(inputRate))", sentence,
                    ]
                    try say.run()
                    say.waitUntilExit()
                    guard say.terminationStatus == 0 else {
                        throw CleanExit.message("say failed for voice \(voice).")
                    }
                }
                let audio = try AudioFileReader.read(contentsOf: url)
                clips.append(
                    SpokenClip(samples: audio.samples, words: TextNormaliser.standard.words(sentence)))
            }
        }
        return clips
    }
}
