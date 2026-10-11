// The `seam-score` command: what cutting a long dictation into pieces does at each seam, against one decode.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Speaks the long-form corpus, decodes each clip whole and as the live path cuts it, and scores every seam.
struct SeamScoreProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "seam-score",
        abstract: "Count stray stops, wrong capitals and doubled or lost words at long dictations' seams."
    )

    @Option(name: .long, help: "Where the synthesised long-form clips are written.")
    var clipsPath = ".uttrflow-eval/long-form-clips"

    @Option(name: .long, help: "Voice for `say`; the system voice when absent.")
    var voice: String?

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, help: "Load the model from this folder instead of the model store.")
    var modelFolder: String?

    @Option(name: .long, help: "Seconds between the live path's looks for a cut.")
    var poll = 1.0

    @Option(name: .long, help: "The stored seam score: compared with, or written by --save-baseline.")
    var baseline = "Scripts/seam_score_baseline.json"

    @Flag(name: .long, help: "Write this run as the baseline instead of comparing with it.")
    var saveBaseline = false

    @Flag(name: .long, help: "Exit non-zero when any clip counts more of any artefact than the baseline.")
    var failOnRegression = false

    @Flag(name: .long, help: "Print each clip's pieces beside its one-pass text.")
    var list = false

    func validate() throws {
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

        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rate = AudioSamples.canonicalSampleRate
        var run = SeamRun()
        print("whisperKit \(model.variant); long-form corpus, live cuts polled every \(poll) s")
        print("| Clip | Seconds | Seams | Stray stops | Wrong capitals | Duplicated | Dropped |")
        print("|---|---|---|---|---|---|---|")
        for testCase in EvaluationCorpus.longForm {
            let name = voice.map { "\(testCase.id)-\($0)" } ?? testCase.id
            let clip = directory.appendingPathComponent("\(name).wav")
            if !FileManager.default.fileExists(atPath: clip.path) {
                guard SaySynthesizer().speak(LongFormRecipe(testCase).script, voice: voice, to: clip) else {
                    throw CleanExit.message("`say` could not speak \(testCase.id).")
                }
            }
            let samples = try AudioFileReader.read(contentsOf: clip).samples
            let decode: (Range<Int>) async throws -> String = { range in
                try await speech.transcribe(.canonical(Array(samples[range])), options: .init()).text
            }
            let whole = try await decode(samples.indices)
            var pieces: [String] = []
            for range in RetryParity.livePieces(
                samples, sampleRate: rate, pollSamples: Int(poll * Double(rate)))
            {
                pieces.append(try await decode(range))
            }
            let score = SeamScore(whole: whole, pieces: pieces)
            run.record(score, for: testCase.id)
            let total = score.total
            let seconds = String(format: "%.1f", Double(samples.count) / Double(rate))
            print(
                "| \(testCase.id) | \(seconds) | \(score.seams.count) | \(total.strayStops) | "
                    + "\(total.wrongCapitals) | \(total.duplicated) | \(total.dropped) |")
            if list {
                print("    whole:  \(whole)")
                print("    pieces: \(pieces.joined(separator: " | "))")
            }
        }
        let total = run.total
        let sums = [total.strayStops, total.wrongCapitals, total.duplicated, total.dropped]
        print("| all | | | " + sums.map(String.init).joined(separator: " | ") + " |")
        try judge(run)
    }

    /// Writes the run as the baseline, or names every clip and kind that rose above it.
    private func judge(_ run: SeamRun) throws {
        let url = URL(fileURLWithPath: baseline)
        if saveBaseline {
            try run.write(to: url)
            print("\nBaseline written to \(baseline).")
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("\nNo baseline at \(baseline); write one with --save-baseline.")
            return
        }
        let rises = run.rises(over: try SeamRun.read(from: url))
        guard !rises.isEmpty else {
            print("\nNo clip counts more of any artefact than \(baseline).")
            return
        }
        print("\nMore artefacts than \(baseline):")
        for line in rises { print("  \(line)") }
        if failOnRegression { throw ExitCode.failure }
    }
}
