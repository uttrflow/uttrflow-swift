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
        let completions = await scorer.completions(for: typed, in: situation)
        print("completions for \(typed.debugDescription) in \(application):")
        guard !completions.isEmpty else {
            print("  (none)")
            return
        }
        for completion in completions { print("  \(completion)") }
    }

    /// Every fixture in turn, each timed, with the rates that decide whether a phase held.
    private func measure(with scorer: MLXCandidateScorer) async {
        let chosen = Fixture.all.filter { only.map($0.name.hasPrefix) ?? true }
        // One pass first, so the Metal kernels are compiled before anything is timed.
        if let first = chosen.first {
            _ = await scorer.completions(for: first.typed, in: first.situation)
        }
        var rows: [(Fixture, Int, Bool, Bool, String)] = []
        for fixture in chosen {
            let started = ContinuousClock.now
            let completions = await scorer.completions(for: fixture.typed, in: fixture.situation)
            let elapsed = Int((ContinuousClock.now - started) / .milliseconds(1))
            let hit = fixture.hits(completions)
            let conforms = fixture.conforms(completions)
            let first = completions.first ?? "-"
            rows.append((fixture, elapsed, hit, conforms, first))
            print(
                "\(hit ? "✓" : "✗")\(conforms ? "✓" : "✗") \(String(elapsed).leftPadded(to: 5))ms  "
                    + "\(fixture.name.leftPadded(to: 18))  \(first.debugDescription)")
        }
        print("")
        for category in Set(chosen.map(\.category)).sorted() {
            let inCategory = rows.filter { $0.0.category == category }
            let hits = inCategory.filter(\.2).count
            let conforming = inCategory.filter(\.3).count
            print(
                "\(category.leftPadded(to: 10))  hit \(hits)/\(inCategory.count)  "
                    + "in register \(conforming)/\(inCategory.count)")
        }
        let times = rows.map(\.1).sorted()
        guard !times.isEmpty else { return }
        let p50 = times[times.count / 2]
        let p95 = times[min(times.count - 1, Int(Double(times.count) * 0.95))]
        print(
            "\nall  hit \(rows.filter(\.2).count)/\(rows.count)  in register \(rows.filter(\.3).count)/\(rows.count)"
                + "  p50 \(p50)ms  p95 \(p95)ms")
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
