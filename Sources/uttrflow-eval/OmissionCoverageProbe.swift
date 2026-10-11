// The `omission-coverage` command: whether voiced audio no recognised word covers predicts a dropped word.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Decodes invented sentences full of negators, articles, auxiliaries and numbers, and scores the coverage signal.
struct OmissionCoverageProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "omission-coverage",
        abstract: "Measure whether an uncovered voiced run predicts a word the recogniser left out."
    )

    /// Invented sentences, each holding words whose loss changes the meaning.
    static let sentences = """
        i do not want the second build tonight
        there is no reason to ship a broken release
        she has not seen the three new tickets
        we will never merge a change without a test
        the cache was not cleared before the run
        it is a bug and not a feature
        you should not push to the main branch
        he did not say there were twelve errors
        nothing in the log points at a crash
        do not delete the file until the backup is done
        they can not reach the server from the office
        a token is not a password and should not be logged
        the meeting is at four and not at five
        we have seven open issues and no owner
        none of the tests failed on the first try
        the queue was empty and the job did not start
        """.split(separator: "\n").map(String.init)

    @Option(name: .long, help: "Where the generated clips are written.")
    var clipsPath = ".uttrflow-eval/omission-clips"

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Synthetic voices that read the sentences.")
    var voices = ["Samantha", "Daniel", "Rishi"]

    @Option(name: .long, parsing: .upToNextOption, help: "Speaking rates, in words per minute.")
    var rates = [175, 260, 340]

    @Option(
        name: .long,
        help: "A tab-separated file of recorded clips (audio path, reference) to use instead of voices.")
    var manifest: String?

    @Option(name: .long, help: "Seconds either side within which a run and a deletion count as near.")
    var tolerance = 0.12

    @Option(name: .long, help: "The rate the clips are synthesised at.")
    var inputRate = 48_000.0

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

        var clips: [OmissionCoverage.Clip] = []
        var spokenSeconds = 0.0
        for (reference, path) in try inputs(in: directory) {
            Terminal.show("\r  \(clips.count + 1)          ")
            let audio = try AudioFileReader.read(contentsOf: path)
            let rate = Double(audio.sampleRate)
            let transcription = try await speech.transcribe(audio, options: .automatic)
            let voiced =
                VoiceActivity.speechRange(in: audio.samples, sampleRate: audio.sampleRate).map {
                    TimeSpan(start: Double($0.lowerBound) / rate, end: Double($0.upperBound) / rate)
                } ?? TimeSpan(start: 0, end: Double(audio.samples.count) / rate)
            spokenSeconds += voiced.length
            clips.append(
                OmissionCoverage.Clip(
                    reference: TextNormaliser.standard.words(reference), words: timedWords(transcription),
                    voiced: voiced))
        }
        Terminal.clearLine()
        let words = clips.map(\.reference.count).reduce(0, +)
        let source = manifest ?? "voices \(voices.joined(separator: ", ")); rates \(rates) wpm"
        print("whisperKit \(model.variant); \(source)")
        print(
            String(
                format: "%d clips, %d reference words, %.1f words per voiced second", clips.count, words,
                Double(words) / max(spokenSeconds, 0.001)))
        let byLength = OmissionCoverage.sweep.map {
            ($0, OmissionCoverage.tally(clips, minimum: $0, tolerance: tolerance))
        }
        print("\n| Class | Deletions |")
        print("|---|---|")
        for kind in OmissionClass.allCases {
            print("| \(kind.rawValue) | \(byLength[0].1[kind]?.deletions ?? 0) |")
        }
        print(
            "\n| d (ms) | Runs | Precision | Recall | False alarms per 100 words |"
                + OmissionClass.allCases
                .map { " Recall \($0.rawValue) |" }.joined())
        print("|---|---|---|---|---|" + String(repeating: "---|", count: OmissionClass.allCases.count))
        for (length, tally) in byLength {
            let all = tally[nil] ?? OmissionCoverage.Tally()
            let perClass = OmissionClass.allCases.map { " \(share(tally[$0]?.recall)) |" }.joined()
            print(
                "| \(Int(length * 1000)) | \(all.runs) | \(share(all.precision)) | \(share(all.recall)) | "
                    + "\(all.falseAlarmsPer100Words.map { String(format: "%.1f", $0) } ?? "–") |" + perClass)
        }
        let go = OmissionCoverage.isGo(byLength.compactMap { $0.1[nil] })
        print(
            "\n\(go ? "GO" : "NO-GO"): precision floor \(share(OmissionCoverage.precisionFloor)) "
                + "\(go ? "reached" : "not reached") at any swept length.")
    }

    private func share(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0 * 100) } ?? "–" }

    /// Every recognised word with timings, split into normalised words that share their word's span.
    private func timedWords(_ transcription: Transcription) -> [TimedWord] {
        transcription.segments.flatMap(\.words).flatMap { word -> [TimedWord] in
            guard let start = word.start, let end = word.end else { return [] }
            return TextNormaliser.standard.words(word.text).map {
                TimedWord(
                    text: $0,
                    start: Double(start.components.seconds) + Double(start.components.attoseconds) / 1e18,
                    end: Double(end.components.seconds) + Double(end.components.attoseconds) / 1e18)
            }
        }
    }

    /// The clips to decode: the manifest's recordings, or each sentence synthesised in each voice and rate.
    private func inputs(in directory: URL) throws -> [(reference: String, path: URL)] {
        if let manifest {
            let base = URL(fileURLWithPath: manifest).deletingLastPathComponent()
            return try String(contentsOfFile: manifest, encoding: .utf8).split(separator: "\n").compactMap {
                line in
                let fields = line.split(separator: "\t").map(String.init)
                return fields.count >= 2
                    ? (fields[1], URL(fileURLWithPath: fields[0], relativeTo: base)) : nil
            }
        }
        return try Self.sentences.flatMap { sentence in
            try voices.flatMap { voice in
                try rates.map { (sentence, try clip(sentence, voice: voice, rate: $0, in: directory)) }
            }
        }
    }

    /// The sentence read by `voice` at `rate`, synthesised once and reused.
    private func clip(_ text: String, voice: String, rate: Int, in directory: URL) throws -> URL {
        let name = "\(voice)-\(rate)-\(text.split(separator: " ").prefix(4).joined(separator: "_")).wav"
        let url = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = [
                "-v", voice, "-r", "\(rate)", "-o", url.path, "--data-format=LEF32@\(Int(inputRate))", text,
            ]
            try say.run()
            say.waitUntilExit()
            guard say.terminationStatus == 0 else {
                throw CleanExit.message("say failed for voice \(voice).")
            }
        }
        return url
    }
}
