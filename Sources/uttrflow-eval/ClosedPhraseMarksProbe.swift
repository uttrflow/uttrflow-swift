// The `closed-phrase-marks` command: how often the recogniser writes a comma or stop inside a closed phrase.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowSpeech

/// Speaks invented sentences with a hesitation after a closed-class word and counts the marks the recogniser puts there.
struct ClosedPhraseMarksProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "closed-phrase-marks",
        abstract:
            "Count recogniser commas and stops after a determiner, preposition, auxiliary, \"and\" or \"of\"."
    )

    @Option(name: .long, help: "Where the generated clips are written.")
    var clipsPath = ".uttrflow-eval/closed-phrase-clips"

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(
        name: .long, parsing: .upToNextOption,
        help: "Milliseconds of hesitation spoken after the closed word.")
    var pauses: [Int] = [0, 400, 800, 1500]

    /// Invented sentences, the hesitation falls where `|` stands, right after a closed-class word.
    static let sentences = [
        "please check the | build before lunch",
        "we went to the | store on the corner",
        "she put the keys on | the green table",
        "the report is in | the shared folder",
        "the parcel will | arrive on friday",
        "the meeting has | moved to thursday",
        "bring the charger and | the spare cable",
        "a cup of | tea would be lovely",
        "most of | the plants need water",
        "they were | late for the train",
        "move a | chair into the hall",
        "we can | meet after the class",
    ]

    static let voices = ["Samantha", "Daniel", "Karen", "Rishi"]

    /// The closed classes the legality table forbids a mark after.
    static let classes: [(name: String, words: Set<String>)] = [
        (
            "determiner",
            ["the", "a", "an", "this", "that", "my", "our", "your", "their", "his", "her", "its"]
        ),
        ("preposition", ["to", "in", "on", "at", "for", "with", "from", "into", "by", "about"]),
        (
            "auxiliary",
            ["is", "are", "was", "were", "will", "can", "has", "have", "had", "would", "should", "do"]
        ),
        ("and", ["and"]),
        ("of", ["of"]),
    ]

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

        var marks = 0
        var illegal: [String: (comma: Int, stop: Int)] = [:]
        var atPause: [Int: (comma: Int, stop: Int, clips: Int)] = [:]
        for pause in pauses {
            for voice in Self.voices {
                for (index, sentence) in Self.sentences.enumerated() {
                    let spoken = sentence.replacingOccurrences(
                        of: " | ", with: pause == 0 ? " " : " [[slnc \(pause)]] ")
                    let url = directory.appendingPathComponent("\(voice)-\(index)-\(pause).wav")
                    try Self.synthesise(spoken, voice: voice, to: url)
                    let audio = try AudioFileReader.read(contentsOf: url)
                    let text = try await speech.transcribe(.canonical(audio.samples), options: .init()).text
                    let found = Self.marks(in: text)
                    marks += found.total
                    var cell = atPause[pause] ?? (0, 0, 0)
                    cell.clips += 1
                    for hit in found.illegal {
                        var row = illegal[hit.kind] ?? (0, 0)
                        if hit.mark == "," {
                            row.comma += 1; cell.comma += 1
                        } else {
                            row.stop += 1; cell.stop += 1
                        }
                        illegal[hit.kind] = row
                        print("  \(voice) \(pause) ms: \(text)")
                    }
                    atPause[pause] = cell
                }
            }
        }
        print("\nRecogniser marks: \(marks)")
        print("\n| Class | Comma | Stop |\n|---|---|---|")
        for entry in Self.classes {
            let row = illegal[entry.name] ?? (0, 0)
            print("| \(entry.name) | \(row.comma) | \(row.stop) |")
        }
        print("\n| Pause ms | Clips | Illegal comma | Illegal stop |\n|---|---|---|---|")
        for pause in pauses {
            let cell = atPause[pause] ?? (0, 0, 0)
            print("| \(pause) | \(cell.clips) | \(cell.comma) | \(cell.stop) |")
        }
    }

    /// Every comma, stop, semicolon and question mark, and those that follow a closed-class word.
    static func marks(in text: String) -> (total: Int, illegal: [(kind: String, mark: Character)]) {
        var total = 0
        var illegal: [(kind: String, mark: Character)] = []
        for token in text.split(separator: " ") {
            guard let last = token.last, ",.;?".contains(last) else { continue }
            total += 1
            let word = token.dropLast().lowercased()
            if let kind = classes.first(where: { $0.words.contains(word) }) {
                illegal.append((kind.name, last == "," ? "," : "."))
            }
        }
        return (total, illegal)
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
