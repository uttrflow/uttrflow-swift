import ArgumentParser
import Foundation
import UttrflowLocalModel
import UttrflowPredict

/// Asks the local model to complete a partial line, to watch generation work outside the app.
struct Complete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "complete",
        abstract: "Show the completions the local model generates for a partial line."
    )

    @Argument(help: "The partial text to complete.")
    var typed: String

    @Option(name: .long, help: "The application the caret is in, e.g. Terminal, DBeaver, Safari.")
    var application = "Terminal"

    @Option(name: .long, help: "The page or directory the field belongs to, if any.")
    var document: String?

    @Option(name: .long, help: "Which model to run. Defaults to the one the app uses for suggestions.")
    var model = "gemma-3-1b-it-qat-4bit"

    func run() async throws {
        guard let chosen = LocalModel.named(model) else {
            print("no such model: \(model)")
            return
        }
        let scorer = MLXCandidateScorer(model: chosen)
        try await scorer.prepare { fraction in
            FileHandle.standardError.write(Data("\r  loading \(Int(fraction * 100))% ".utf8))
        }
        FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))
        let situation = GenerationSituation(application: application, document: document)
        let completions = await scorer.completions(for: typed, in: situation)
        print("completions for \(typed.debugDescription) in \(application):")
        guard !completions.isEmpty else {
            print("  (none)")
            return
        }
        for completion in completions { print("  \(completion)") }
    }
}
