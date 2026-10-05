// The `synthesise` command: fills a corpus with the system synthesiser reading English and code-mixed passages.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval

/// Writes a repeatable corpus that needs no microphone, for comparing recognisers on one Mac.
struct SynthesiseCorpus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "synthesise",
        abstract: "Have the system synthesiser read the English and code-mixed passages into a corpus."
    )

    @Option(name: .long, help: "Where the synthesised corpus is written; keep it apart from a recorded one.")
    var corpusPath: String

    @Option(name: .long, help: "The `say` voice that reads every passage.")
    var voice = "Samantha"

    @Option(name: .long, help: "The Indian-English `say` voice that reads the code-mixed Hinglish passages.")
    var codeMixingVoice = "Rishi"

    func run() async throws {
        let store = TranscriptionCorpusStore(directory: URL(fileURLWithPath: corpusPath))
        // Whole Hindi passages stay unread: a Latin-script voice reading them measures the synthesiser.
        let english = store.remaining().filter { $0.language == .english }
        let mixed = store.remaining(from: TranscriptionCorpus.codeMixing)
        try synthesise(english, voice: voice, into: store)
        try synthesise(mixed, voice: codeMixingVoice, into: store)
        print("Synthesised \(english.count + mixed.count) passages into \(corpusPath).")
    }

    private func synthesise(
        _ passages: [TranscriptionCase], voice: String, into store: TranscriptionCorpusStore
    ) throws {
        guard !passages.isEmpty else { return }
        let resolved = resolveVoice(requested: voice, catalogue: SayVoiceCatalogue())
        guard let installed = resolved.installed else {
            throw CleanExit.message("Voice '\(voice)' is not installed; `say -v ?` lists those that are.")
        }
        let cohort = RecordingCohort(
            id: "synthesised-\(installed.lowercased())", speaker: installed, setting: "say, 16 kHz")
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("uttrflow-say.wav")
        for passage in passages {
            guard SaySynthesizer().speak(passage.prompt, voice: installed, to: scratch) else {
                throw CleanExit.message("`say` could not read \(passage.id).")
            }
            let wav = try Data(contentsOf: scratch)
            let audio = try AudioFileReader.read(contentsOf: scratch)
            let recorded = RecordedPassage(
                passage: passage, recordedAt: Date(),
                durationSeconds: Double(audio.samples.count) / Double(audio.sampleRate),
                sampleRate: audio.sampleRate, cohort: cohort,
                recordingIdentity: RecordingIdentity.digest(of: wav))
            try store.save(recorded, audio: wav)
        }
    }
}
