import ArgumentParser
import Foundation
import UttrflowLocalModel
import UttrflowPredict

/// Asks the local model how likely each remembered line is after what was typed, to watch verification judge outside the app.
struct Score: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "score",
        abstract: "Print the log-likelihood the local model gives each candidate after the typed context."
    )

    @Option(name: .long, help: "What has been typed so far, e.g. \"git c\".")
    var context: String

    @Option(name: .long, parsing: .singleValue, help: "A whole candidate line to score; repeat for several.")
    var candidate: [String]

    @Option(name: .long, help: "Which model to run: gemma3, gemma3Small, or a repository name.")
    var model = "gemma3"

    @Option(name: .long, help: "Text put before both the context and every candidate, to try a framing.")
    var preamble = ""

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
        print(
            "scores after \(context.debugDescription) with \(chosen.shortName), floor \(Verification.plausibilityFloor):"
        )
        let clock = ContinuousClock()
        for line in candidate {
            let started = clock.now
            let judged = await scorer.judgedTokens(of: preamble + line, following: preamble + context)
            let milliseconds = Int(started.duration(to: clock.now) / .milliseconds(1))
            let score =
                judged.isEmpty ? nil : judged.map(\.logProbability).reduce(0, +) / Double(judged.count)
            let shown = score.map { String(format: "%8.3f", $0) } ?? "    none"
            let verdict =
                score.map { Verification.objects(to: .scored($0)) ? "objects" : "allows " } ?? "silent "
            print("  \(shown)  \(verdict)  \(String(milliseconds).padded(to: 6))ms  \(line.debugDescription)")
            let perToken = judged.map {
                "\($0.text.debugDescription)=\(String(format: "%.2f", $0.logProbability))"
            }
            print("            \(perToken.joined(separator: " "))")
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
