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

    @Option(name: .long, help: "Which model to run: gemma3, gemma3Small, apple, or a repository name.")
    var model = "gemma3"

    @Flag(name: .long, help: "Run every fixture and report hit rate, register conformance and latency.")
    var fixtures = false

    @Option(name: .long, help: "Only fixtures whose name starts with this, e.g. chat/ or terminal/.")
    var only: String?

    @Option(name: .long, help: "Run only the first N fixtures left after --only.")
    var limit: Int?

    @Option(name: .long, help: "Write every fixture's result and the summary as JSON to this path.")
    var json: String?

    @Flag(
        name: .long, help: "Record how each pass ended and every word the model wrote, so a miss can be read."
    )
    var raw = false

    @Option(name: .long, help: "Run only the fixtures that missed in this earlier run's JSON.")
    var failedIn: String?

    func run() async throws {
        let generator: any CandidateGenerating
        if model == "apple" {
            // Apple's model is bundled with the system and loads itself; there is nothing to download or warm.
            let apple = AppleCandidateGenerator()
            guard await apple.isReady else {
                print("Apple's on-device model is not available: turn on Apple Intelligence and try again")
                return
            }
            generator = apple
        } else {
            guard let chosen = Self.model(named: model) else {
                print("no such model: \(model)")
                return
            }
            let scorer = MLXCandidateScorer(model: chosen)
            try await scorer.prepare { fraction in
                FileHandle.standardError.write(Data("\r  loading \(Int(fraction * 100))% ".utf8))
            }
            FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))
            generator = scorer
        }
        if fixtures {
            await measure(with: generator)
        } else {
            await complete(typed ?? "", with: generator)
        }
    }

    /// One line, printed with everything the model offered for it.
    private func complete(_ typed: String, with scorer: any CandidateGenerating) async {
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
    private func measure(with scorer: any CandidateGenerating) async {
        var chosen = Fixture.all.filter { only.map($0.name.hasPrefix) ?? true }
        if let failedIn {
            guard let missed = Self.misses(recordedIn: failedIn) else {
                print("could not read the earlier run at \(failedIn)")
                return
            }
            chosen = chosen.filter { missed.contains($0.name) }
        }
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
            var words: String?
            do {
                // Only the local model can show its pass raw; Apple's answers in text alone.
                if raw, let scorer = scorer as? MLXCandidateScorer {
                    let pass = try await scorer.pass(for: fixture.typed, in: fixture.situation)
                    completions = pass?.completions ?? []
                    words = pass.map { "[\($0.stopReason)] \($0.text)" } ?? "[not asked]"
                } else {
                    completions = try await scorer.completions(for: fixture.typed, in: fixture.situation)
                }
            } catch {
                failure = "error: \(error)"
            }
            let elapsed = Int((ContinuousClock.now - started) / .milliseconds(1))
            let result = FixtureResult(
                name: fixture.name, category: fixture.category, typed: fixture.typed,
                hit: fixture.hits(completions), conforms: fixture.conforms(completions), elapsedMs: elapsed,
                first: failure ?? completions.first, raw: words)
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

    /// The names of the fixtures an earlier run's JSON records as missed, or nothing when the file cannot be read.
    private static func misses(recordedIn path: String) -> Set<String>? {
        struct Earlier: Decodable {
            struct Result: Decodable {
                let name: String
                let hit: Bool
            }
            let results: [Result]
        }
        guard let data = FileManager.default.contents(atPath: path),
            let earlier = try? JSONDecoder().decode(Earlier.self, from: data)
        else { return nil }
        return Set(earlier.results.filter { !$0.hit }.map(\.name))
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
