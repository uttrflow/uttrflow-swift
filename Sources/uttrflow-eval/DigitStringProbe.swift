// The `digit-strings` command: exact digit and code spans on the recogniser's text and after the rules.
import ArgumentParser
private import Foundation
private import UttrflowAI
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Speaks the digit-string class in several voices and scores each span before and after the rules.
struct DigitStringProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "digit-strings",
        abstract: "Score digit strings and codes, character for character, before and after the rules."
    )

    @Option(name: .long, help: "Where the generated clips are written.")
    var clipsPath = ".uttrflow-eval/digit-string-clips"

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, parsing: .upToNextOption, help: "macOS voices that read the sentences.")
    var voices: [String] = SpokenClips.accentVoices

    @Option(name: .long, help: "Where each model stage runs: shipping, gpu, neuralEngine or all.")
    var compute = SpeechComputePlan.shipping.rawValue

    @Option(name: .long, help: "The stored per-shape counts this run is compared with.")
    var baseline = "Scripts/digit_string_baseline.json"

    @Flag(name: .long, help: "Write this run as the baseline instead of comparing with it.")
    var saveBaseline = false

    @Flag(name: .long, help: "Exit non-zero when a shape has fewer exact cases than the baseline.")
    var failOnRegression = false

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
            kind: .whisperKit, model: model, modelFolder: store.location(of: model),
            compute: SpeechComputePlan(rawValue: compute) ?? .shipping)
        try await speech.prepare()
        let rules = RuleBasedTransformer()
        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var outcomes: [DigitStringOutcome] = []
        for voice in voices {
            for testCase in DigitStringCorpus.all {
                let url = directory.appendingPathComponent("\(voice)-\(testCase.id).wav")
                try Self.synthesise(testCase.spoken, voice: voice, to: url)
                let audio = try AudioFileReader.read(contentsOf: url)
                let transcription = try await speech.transcribe(
                    .canonical(audio.samples), options: .init(languageHint: .english))
                let cleaned = try await rules.transform(TransformationRequest(transcription: transcription))
                let outcome = DigitStringOutcome(
                    testCase, raw: transcription.text, final: cleaned.text, record: cleaned.cleaning)
                if !outcome.rawExact || !outcome.finalExact {
                    print(
                        "  \(voice) \(testCase.id) \(testCase.spans): raw \"\(transcription.text)\" "
                            + "final \"\(cleaned.text)\"")
                }
                outcomes.append(outcome)
            }
        }
        let report = DigitStringReport(outcomes)
        print(
            "\nPROBE digit strings: \(DigitStringCorpus.all.count) cases x \(voices.count) voices\n\(report.table)"
        )
        for row in report.worseAfterRules {
            print("Worse after the rules: \(row.shape.rawValue)")
        }
        try judge(
            DigitStringBaseline(
                label: "\(model.variant), \(compute), \(voices.joined(separator: " "))", recordedAt: Date(),
                report: report))
    }

    /// Saves the run as the baseline, or names the shapes that fell since it and fails on them when asked.
    private func judge(_ measured: DigitStringBaseline) throws {
        let url = URL(fileURLWithPath: baseline)
        if saveBaseline {
            try measured.write(to: url)
            print("\nBaseline written to \(baseline).")
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("\nNo baseline at \(baseline); write one with --save-baseline.")
            return
        }
        switch try DigitStringBaseline.read(from: url).worsened(in: measured) {
        case .failure(let incomparable):
            print("\nNot compared with \(baseline): \(incomparable.reason)")
            if failOnRegression { throw ExitCode.failure }
        case .success(let fell):
            let named = fell.map(\.rawValue).joined(separator: ", ")
            print("\nAgainst \(baseline): " + (fell.isEmpty ? "no shape fell." : "fewer exact in \(named)"))
            if failOnRegression, !fell.isEmpty { throw ExitCode.failure }
        }
    }

    private static func synthesise(_ text: String, voice: String, to url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", url.path, "--data-format=LEF32@48000", text]
        try say.run()
        say.waitUntilExit()
        guard say.terminationStatus == 0 else { throw CleanExit.message("say failed for voice \(voice).") }
    }
}
