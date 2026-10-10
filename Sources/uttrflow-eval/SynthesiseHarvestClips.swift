// The `synthesise-harvest` command: system voices read an invented text set into a `harvest-confusions` manifest.
import ArgumentParser
private import Foundation
private import UttrflowEval

/// Writes one clip per sentence, voice and rate, plus the manifest `harvest-confusions` decodes them from.
struct SynthesiseHarvestClips: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "synthesise-harvest",
        abstract: "Have system voices read an invented text set into a harvest-confusions manifest.",
        discussion: """
            Each line of --text is one sentence; without it, the English fit-split passages are read, so \
            coverage on the calibration split is never measured on text the table was built from. \
            Each voice is written Name:class; the class is the table's group, and Name@rate its speaker.
            """
    )

    @Option(name: .long, help: "Where the clips and manifest.tsv are written.")
    var outputDirectory: String

    @Option(name: .long, help: "A file of invented sentences, one per line.")
    var text: String?

    @Option(name: .customLong("voice"), help: "A `say` voice and its class, as Name:class. Repeatable.")
    var voiceArguments = ["Samantha:en_US", "Daniel:en_GB", "Rishi:en_IN"]

    @Option(name: .customLong("rate"), help: "A `say -r` rate in words per minute. Repeatable.")
    var rates = [160, 220]

    func validate() throws {
        if voiceArguments.contains(where: { SyntheticHarvestSource.Voice(argument: $0) == nil }) {
            throw ValidationError("Each --voice is Name:class, for example Samantha:en_US.")
        }
        if rates.isEmpty || rates.contains(where: { $0 <= 0 }) {
            throw ValidationError("Each --rate is a positive number of words per minute.")
        }
    }

    func run() throws {
        let voices = voiceArguments.compactMap(SyntheticHarvestSource.Voice.init(argument:))
        let installed = SayVoiceCatalogue().installedVoiceNames()
        if let missing = voices.first(where: { !installed.contains($0.name) }) {
            throw CleanExit.message("Voice '\(missing.name)' is not installed; `say -v ?` lists those that are.")
        }
        let sentences =
            try text.map { try String(contentsOfFile: $0, encoding: .utf8).components(separatedBy: .newlines) }
            ?? TranscriptionCorpus.all.filter { $0.language == .english && $0.split == .fit }.map(\.romanised)
        let takes = SyntheticHarvestSource.takes(sentences: sentences, voices: voices, rates: rates)
        let directory = URL(fileURLWithPath: outputDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, take) in takes.enumerated() {
            Terminal.show("\r  \(index + 1) of \(takes.count)          ")
            let destination = directory.appendingPathComponent(take.file)
            guard SaySynthesizer(rate: take.rate).speak(take.text, voice: take.voice.name, to: destination) else {
                throw CleanExit.message("`say` could not write \(take.file).")
            }
        }
        Terminal.clearLine()
        let manifest = directory.appendingPathComponent("manifest.tsv")
        try SyntheticHarvestSource.manifest(takes).write(to: manifest, atomically: true, encoding: .utf8)
        print("Wrote \(takes.count) clips and \(manifest.path)")
    }
}
