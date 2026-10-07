// The `accent` command: which accent classes the sound key misses and the opening-letters gate rejects.
import ArgumentParser
private import Foundation
private import UttrflowAI
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Has accented synthetic voices read minimal-pair words and counts which correction gate could reach each miss.
struct AccentProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "accent",
        abstract: "Measure which accent classes the sound key misses and the opening-letters gate rejects."
    )

    @Option(name: .long, help: "Where the synthesised clips are kept between runs.")
    var clipsPath = ".uttrflow-eval/accent-clips"

    @Option(name: .long, help: "Where each heard word is written, one tab-separated row per clip and hint.")
    var rowsPath = ".uttrflow-eval/accent-rows.tsv"

    @Option(name: .long, parsing: .upToNextOption, help: "The `say` voices that read every sentence.")
    var voices = [
        "Rishi", "Aman (English (India))", "Tara (English (India))",
        "Thomas", "Jacques", "Eddy (French (France))", "Flo (French (France))",
        "Tessa", "Moira", "Karen", "Samantha", "Daniel",
    ]

    /// Hindi is hinted only for these, since a Hindi hint on a voice that cannot speak Hindi measures nothing.
    @Option(name: .long, parsing: .upToNextOption, help: "Voices also transcribed under a Hindi hint.")
    var hindiVoices = ["Rishi", "Aman (English (India))", "Tara (English (India))"]

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

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
        let installed = SayVoiceCatalogue().installedVoiceNames()
        let missing = voices.filter { !installed.contains($0) }
        guard missing.isEmpty else {
            let names = missing.joined(separator: ", ")
            throw CleanExit.message("Not installed: \(names); `say -v ?` lists those that are.")
        }
        let speech = SpeechEngineFactory.make(
            kind: .whisperKit, model: model, modelFolder: store.location(of: model))
        try await speech.prepare()
        print("Engine: whisperKit \(model.variant) weights \(model.weightsRevision)")
        let hindiNames = hindiVoices.joined(separator: ", ")
        print("Voices: \(voices.joined(separator: ", ")); Hindi hint also for \(hindiNames)")

        let items = AccentProbeCorpus.items
        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var rows: [AccentRow] = []
        for voice in voices {
            let hints = ["en"] + (hindiVoices.contains(voice) ? ["hi"] : [])
            for (index, item) in items.enumerated() {
                Terminal.show("\r  \(voice) \(index + 1)/\(items.count)")
                let clip = directory.appendingPathComponent("\(voice.filter { $0.isLetter })-\(index).wav")
                if !FileManager.default.fileExists(atPath: clip.path) {
                    guard SaySynthesizer().speak(item.sentence, voice: voice, to: clip) else {
                        throw CleanExit.message("`say` could not read item \(index) in \(voice).")
                    }
                }
                let audio = try AudioFileReader.read(contentsOf: clip)
                for hint in hints {
                    let options = TranscriptionOptions(languageHint: LanguageCode(hint))
                    let text = try await speech.transcribe(audio, options: options).text
                    rows.append(
                        AccentRow(
                            voice: voice, hint: hint, item: item, heard: Self.heard(in: text, around: item),
                            transcript: text))
                }
            }
        }
        Terminal.clearLine()
        try rows.map(\.line).joined(separator: "\n").write(
            to: URL(fileURLWithPath: rowsPath), atomically: true, encoding: .utf8)
        print(AccentTable(rows: rows).markdown)
    }

    /// The words left once the carrier's own word counts are taken off each end, or `nil` when nothing is left.
    static func heard(in transcript: String, around item: AccentProbeItem) -> String? {
        let words = TextNormaliser.standard.words(transcript)
        let before = TextNormaliser.standard.words(item.carrier.before).count
        let after = TextNormaliser.standard.words(item.carrier.after).count
        guard words.count > before + after else { return nil }
        return words[before..<(words.count - after)].joined(separator: " ")
    }
}

/// One clip transcribed under one hint, and what the recogniser hears as the target.
private struct AccentRow {
    let voice: String
    let hint: String
    let item: AccentProbeItem
    let heard: String?
    let transcript: String

    var isRight: Bool { reach?.isSameSpelling ?? false }
    var reach: SoundAlikeReach? {
        heard.flatMap { $0.isEmpty ? nil : SoundAlikeReach(heard: $0, meant: item.word) }
    }
    var line: String {
        [voice, hint, item.accentClass, item.word, heard ?? "<too short>", transcript].joined(separator: "\t")
    }
}

/// Per class: misses, and the share of misses each gate would carry to the word meant.
private struct AccentTable {
    let rows: [AccentRow]

    var markdown: String {
        var lines = [
            "| Class | Hint | Clips | Too short | Misses | (a) key | (b) key + opening | (c) entry spells | (a) - (b) |",
            "|---|---|---|---|---|---|---|---|---|",
        ]
        let classes = AccentProbeCorpus.classes.map(\.0) + ["term in English", "term in Hindi"]
        for name in classes {
            for hint in ["en", "hi"] {
                let group = rows.filter { $0.item.accentClass == name && $0.hint == hint }
                guard !group.isEmpty else { continue }
                let anchored = group.filter { $0.heard != nil }
                let misses = anchored.filter { !$0.isRight }
                let reaches = misses.compactMap(\.reach)
                let key = share(reaches.filter(\.sharesKey).count, of: misses.count)
                let opening = share(reaches.filter(\.passesOpening).count, of: misses.count)
                let spells = share(reaches.filter(\.entrySpells).count, of: misses.count)
                let gap = misses.isEmpty ? "n/a" : String(format: "%.1f", (key ?? 0) - (opening ?? 0))
                lines.append(
                    "| \(name) | \(hint) | \(group.count) | \(group.count - anchored.count) | \(misses.count) | "
                        + "\(text(key)) | \(text(opening)) | \(text(spells)) | \(gap) |")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func share(_ count: Int, of total: Int) -> Double? {
        total == 0 ? nil : Double(count) / Double(total) * 100
    }

    private func text(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0) } ?? "n/a" }
}
