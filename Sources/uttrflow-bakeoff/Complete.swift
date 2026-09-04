import ArgumentParser
import Foundation
import UttrflowLocalModel
import UttrflowPredict

/// Asks the local model to complete a partial line, or holds it to the whole fixture set, outside the app.
struct Complete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "complete",
        abstract: "Show the completions the local model generates, or measure it over the fixture set."
    )

    @Argument(help: "The partial text to complete. Omitted when --fixtures is given.")
    var typed: String?

    @Option(name: .long, help: "The application the caret is in, e.g. Terminal, DBeaver, Safari.")
    var application = "Terminal"

    @Option(name: .long, help: "The page or directory the field belongs to, if any.")
    var document: String?

    @Option(name: .long, help: "Which model to run: gemma3, gemma3Small, or a repository name.")
    var model = "gemma3"

    @Flag(name: .long, help: "Run every fixture and report hit rate, register conformance and latency.")
    var fixtures = false

    @Option(name: .long, help: "Only fixtures whose name starts with this, e.g. chat/ or terminal/.")
    var only: String?

    @Option(name: .long, help: "Run only the first N fixtures left after --only.")
    var limit: Int?

    @Option(name: .long, help: "Write every fixture's result and the summary as JSON to this path.")
    var json: String?

    func run() async throws {
        guard let chosen = Self.model(named: model) else {
            print("no such model: \(model)")
            return
        }
        let scorer = MLXCandidateScorer(model: chosen)
        try await scorer.prepare { fraction in
            FileHandle.standardError.write(Data("\r  loading \(Int(fraction * 100))% ".utf8))
        }
        FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))
        if fixtures {
            await measure(with: scorer)
        } else {
            await complete(typed ?? "", with: scorer)
        }
    }

    /// One line, printed with everything the model offered for it.
    private func complete(_ typed: String, with scorer: MLXCandidateScorer) async {
        let situation = GenerationSituation(application: application, document: document)
        print("completions for \(typed.debugDescription) in \(application):")
        let completions: [String]
        do {
            completions = try await scorer.completions(for: typed, in: situation)
        } catch {
            print("  failed: \(error)")
            return
        }
        guard !completions.isEmpty else {
            print("  (none)")
            return
        }
        for completion in completions { print("  \(completion)") }
    }

    /// Every chosen fixture in turn, each timed, then the rates that decide whether a phase held and the failures.
    private func measure(with scorer: MLXCandidateScorer) async {
        var chosen = Fixture.all.filter { only.map($0.name.hasPrefix) ?? true }
        if let limit { chosen = Array(chosen.prefix(limit)) }
        // One pass first, so the Metal kernels are compiled before anything is timed.
        if let first = chosen.first {
            _ = try? await scorer.completions(for: first.typed, in: first.situation)
        }
        var results: [FixtureResult] = []
        for fixture in chosen {
            let started = ContinuousClock.now
            // A pass that fails is a miss whose answer names the error, so the report tells it from a model with nothing to say.
            var completions: [String] = []
            var failure: String?
            do {
                completions = try await scorer.completions(for: fixture.typed, in: fixture.situation)
            } catch {
                failure = "error: \(error)"
            }
            let elapsed = Int((ContinuousClock.now - started) / .milliseconds(1))
            let result = FixtureResult(
                name: fixture.name, category: fixture.category, typed: fixture.typed,
                hit: fixture.hits(completions), conforms: fixture.conforms(completions), elapsedMs: elapsed,
                first: failure ?? completions.first)
            results.append(result)
            print(result.row)
        }
        let report = FixtureReport(results: results)
        report.printSummary()
        report.printFailures()
        guard let json else { return }
        do {
            try report.write(to: json)
            print("\nwritten to \(json)")
        } catch {
            print("\ncould not write \(json): \(error)")
        }
    }

    /// The names the app's two Gemma sizes go by, beside every repository name the bake-off knows.
    private static func model(named name: String) -> LocalModel? {
        switch name {
        case "gemma3": .gemma3
        case "gemma3Small": .gemma3Small
        default: LocalModel.named(name)
        }
    }
}

extension String {
    /// The string with spaces in front until it is this wide, so a column of numbers lines up.
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
