// The `raw-marks` command: the recogniser's own marks and case, scored per mark and per class.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Speaks the marked English and Hinglish passages, transcribes them, and scores what the engine returned, after its repeat and marker clean-up and before any tidier.
struct RawMarksProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "raw-marks",
        abstract:
            "Score the recogniser's own commas, stops, question marks and capitals, per mark and per class."
    )

    @Option(name: .long, help: "Where the generated clips are written.")
    var clipsPath = ".uttrflow-eval/raw-marks-clips"

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, help: "The `say` voice that reads the English passages.")
    var englishVoice = "Samantha"

    @Option(name: .long, help: "The Indian-English `say` voice that reads the Hinglish passages.")
    var hinglishVoice = "Rishi"

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

        let hinglish = Self.unique(
            TranscriptionCorpus.cases(in: .hinglish) + TranscriptionCorpus.codeMixing)
        let sets: [(name: String, voice: String, cases: [TranscriptionCase])] = [
            ("English", englishVoice, TranscriptionCorpus.cases(in: .english)),
            ("Hinglish", hinglishVoice, hinglish),
        ]
        for set in sets {
            guard resolveVoice(requested: set.voice, catalogue: SayVoiceCatalogue()).installed != nil else {
                throw CleanExit.message(
                    "Voice '\(set.voice)' is not installed; `say -v ?` lists those that are.")
            }
        }

        for set in sets {
            var scores: [RawMarkScore] = []
            var devanagari = 0
            for passage in set.cases {
                let digest = String(passage.romanised.hashValueStable, radix: 16)
                let url = directory.appendingPathComponent("\(set.voice)-\(passage.id)-\(digest).wav")
                if !FileManager.default.fileExists(atPath: url.path) {
                    guard SaySynthesizer().speak(passage.romanised, voice: set.voice, to: url) else {
                        throw CleanExit.message("`say` could not read \(passage.id).")
                    }
                }
                let audio = try AudioFileReader.read(contentsOf: url)
                let text = try await speech.transcribe(.canonical(audio.samples), options: .init()).text
                if text.unicodeScalars.contains(where: { (0x0900...0x097F).contains($0.value) }) {
                    devanagari += 1
                    continue
                }
                scores.append(RawMarkScore(passageID: passage.id, raw: text, reference: passage.romanised))
            }
            Self.print(set.name, voice: set.voice, report: RawMarkReport(scores), devanagari: devanagari)
        }
    }

    private static func unique(_ cases: [TranscriptionCase]) -> [TranscriptionCase] {
        var seen = Set<String>()
        return cases.filter { seen.insert($0.id).inserted }
    }

    private static func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }

    private static func print(_ name: String, voice: String, report: RawMarkReport, devanagari: Int) {
        Swift.print(
            "\n\(name): \(report.scores.count) passages scored (voice \(voice)), \(devanagari) in Devanagari, left out"
        )
        let marks = report.marks
        Swift.print(
            "\n| Mark | Wanted | Written | Right | F1 (95% interval) | Do-nothing F1 |\n|---|---|---|---|---|---|"
        )
        for mark in MarkClass.allCases where (marks.wanted[mark] ?? 0) + (marks.produced[mark] ?? 0) > 0 {
            guard let result = report.f1(of: mark) else { continue }
            Swift.print(
                "| \(mark.rawValue) | \(marks.wanted[mark] ?? 0) | \(marks.produced[mark] ?? 0) "
                    + "| \(marks.correct[mark] ?? 0) | \(percent(result.value)) "
                    + "(\(percent(result.interval.lowerBound))–\(percent(result.interval.upperBound))) | 0.0% |"
            )
        }
        let floor = report.lowerCaseBaseline
        Swift.print(
            "\n| Case class | Words | Recogniser (95% interval) | All lower case |\n|---|---|---|---|")
        for wordClass in CapitalisationClass.allCases {
            guard let result = report.accuracy(of: wordClass) else { continue }
            Swift.print(
                "| \(wordClass.rawValue) | \(report.capitalisation.matched[wordClass] ?? 0) "
                    + "| \(percent(result.value)) (\(percent(result.interval.lowerBound))–\(percent(result.interval.upperBound))) "
                    + "| \(percent(floor.accuracy(of: wordClass) ?? 0)) |")
        }
        let wrongClass = marks.substitutions.flatMap { wanted, written in
            written.map { "\(wanted.rawValue) written as \($0.key.rawValue): \($0.value)" }
        }.sorted()
        if !wrongClass.isEmpty { Swift.print("\nSubstitutions: " + wrongClass.joined(separator: "; ")) }
    }
}
