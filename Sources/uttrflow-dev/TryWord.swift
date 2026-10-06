// The `try-word` command: whether one dictionary word is recognised from a clip, with and without its entry.
import ArgumentParser
import Foundation
import UttrflowAudio
import UttrflowCore
import UttrflowDictionary
import UttrflowPipeline
import UttrflowSpeech

/// Runs the dictionary word probe on an audio file, so CI can check it on a fixture clip.
struct TryWord: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "try-word",
        abstract: "Say whether a dictionary word is recognised from a clip, with and without its entry."
    )

    @Argument(help: "An audio file of the word being said.")
    var file: String

    @Option(name: .long, help: "The entry's spelling.")
    var word: String

    @Option(name: .long, help: "The entry's \"Say it like\", when it has one.")
    var sayItLike: String?

    @Option(name: .shortAndLong, help: "Bias towards a language, e.g. en or hi. Omit to detect.")
    var language: String?

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @OptionGroup var modelsDirectory: ModelsDirectoryOptionGroup

    func validate() throws {
        if let language, LanguageCode(language) == nil {
            throw ValidationError("'\(language)' is not a language code.")
        }
    }

    func run() async throws {
        let model = try resolve(modelVariant)
        let store = try modelsDirectory.store()
        if !store.isInstalled(model) { throw notInstalled(model, in: store) }

        let audio = try AudioFileReader.read(contentsOf: URL(fileURLWithPath: file))
        guard !audio.isEmpty else { throw CleanExit.message("No audio in \(file).") }
        let speech = SpeechEngineFactory.make(
            kind: .whisperKit, model: model, modelFolder: store.location(of: model))
        try await speech.prepare()

        // The entry stands alone, so the answer is about this word and not about the rest of a dictionary.
        let entry = DictionaryEntry(word: word, pronunciation: sayItLike, origin: .added, firstSeen: Date())
        let result = try await DictionaryWordProbe(speech: speech, dictionary: [entry])
            .probe(audio, for: entry, language: language.flatMap(LanguageCode.init))

        print("\n\(result.outcome.resultLine)\n")
        print("  without entry  \(result.withoutEntry)")
        print("  with entry     \(result.withEntry)")
        print("  corrected      \(result.corrected)")
    }
}
