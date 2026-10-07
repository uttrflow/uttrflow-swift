// The `accent-calibration` command: whether a word score means the same for every accent group.
import ArgumentParser
private import Foundation
private import UttrflowAI
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Has each voice read the accent corpus and tabulates, per accent group, how the doubt gate splits right and wrong words.
struct AccentCalibrationProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "accent-calibration",
        abstract:
            "Measure per accent group how many errors the doubt gate sees and how many right words it doubts."
    )

    @Option(name: .long, help: "Where the synthesised clips are kept; shared with `accent`.")
    var clipsPath = ".uttrflow-eval/accent-clips"

    @Option(
        name: .long, parsing: .upToNextOption,
        help: "Voices as name=group; the group is the voice's accent, e.g. Rishi=en-IN.")
    var voices = [
        "Rishi=en-IN", "Thomas=fr-FR", "Tessa=en-ZA", "Moira=en-IE", "Samantha=en-US", "Daniel=en-GB",
        "Karen=en-AU",
    ]

    @Option(
        name: .long,
        help: "A `harvest-confusions` manifest of recorded clips; read in place of the voices when given.")
    var manifest: String?

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    func run() async throws {
        let pairs = try voices.map { entry -> (voice: String, group: String) in
            let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { throw ValidationError("'\(entry)' is not name=group.") }
            return (parts[0], parts[1])
        }
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
        let scored: [ScoredWord]
        if let manifest {
            try await speech.prepare()
            print(
                "Engine: whisperKit \(model.variant) weights \(model.weightsRevision); manifest \(manifest)")
            scored = try await scoreManifest(manifest, speech: speech)
        } else {
            scored = try await scoreVoices(pairs, speech: speech, model: model)
        }
        Terminal.clearLine()
        let rows = GroupCalibration.rows(scored, threshold: DoubtPolicy.certaintyThreshold)
        print(GroupCalibration.markdown(rows))
        let apart = GroupCalibration.standingApart(rows).map(\.group)
        print(
            "\nSeen share apart from the best group: \(apart.isEmpty ? "none" : apart.joined(separator: ", "))"
        )
        print(DoubtStripFloor.summary(DoubtStripFloor.evaluate(scored)))
    }

    /// Aligns every reference word of one decoded clip against what was heard.
    private func align(
        _ sentence: String, group: String, audio: URL, speech: any SpeechEngine
    ) async throws
        -> [ScoredWord]
    {
        let options = TranscriptionOptions(languageHint: LanguageCode("en"))
        let heard = try await speech.transcribe(AudioFileReader.read(contentsOf: audio), options: options)
            .scoredWords
        let reference = TextNormaliser.standard.words(sentence)
        return reference.indices.map { position in
            let outcome = HomophoneConfidence.outcome(reference: reference, index: position, heard: heard)
            return ScoredWord(group: group, score: outcome.score, isRight: !outcome.isError)
        }
    }

    /// Reads the manifest's clips: audio path, reference text, first-language group, speaker.
    private func scoreManifest(_ manifest: String, speech: any SpeechEngine) async throws -> [ScoredWord] {
        let base = URL(fileURLWithPath: manifest).deletingLastPathComponent()
        let lines = try String(contentsOfFile: manifest, encoding: .utf8).split(separator: "\n")
        var scored: [ScoredWord] = []
        for (index, line) in lines.enumerated() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { continue }
            Terminal.show("\r  \(index + 1) of \(lines.count)          ")
            let clip = URL(fileURLWithPath: fields[0], relativeTo: base)
            scored += try await align(fields[1], group: fields[2], audio: clip, speech: speech)
        }
        return scored
    }

    /// Has each `say` voice read the accent corpus, reusing clips already synthesised.
    private func scoreVoices(
        _ pairs: [(voice: String, group: String)], speech: any SpeechEngine, model: SpeechModel
    ) async throws -> [ScoredWord] {
        let installed = SayVoiceCatalogue().installedVoiceNames()
        let missing = pairs.map(\.voice).filter { !installed.contains($0) }
        guard missing.isEmpty else {
            throw CleanExit.message(
                "Not installed: \(missing.joined(separator: ", ")); `say -v ?` lists those that are.")
        }
        try await speech.prepare()
        print("Engine: whisperKit \(model.variant) weights \(model.weightsRevision)")
        print("Threshold: \(DoubtPolicy.certaintyThreshold); voices: \(voices.joined(separator: ", "))")

        let items = AccentProbeCorpus.items
        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var scored: [ScoredWord] = []
        for (voice, group) in pairs {
            for (index, item) in items.enumerated() {
                Terminal.show("\r  \(voice) \(index + 1)/\(items.count)")
                let clip = directory.appendingPathComponent("\(voice.filter { $0.isLetter })-\(index).wav")
                if !FileManager.default.fileExists(atPath: clip.path) {
                    guard SaySynthesizer().speak(item.sentence, voice: voice, to: clip) else {
                        throw CleanExit.message("`say` could not read item \(index) in \(voice).")
                    }
                }
                scored += try await align(item.sentence, group: group, audio: clip, speech: speech)
            }
        }
        return scored
    }
}
