import ArgumentParser
import Foundation
import UttrflowEval
import UttrflowLocalModel
import UttrflowPredict

/// Scores the mid-word calibration set with the local model and reports what each floor keeps and lets through.
struct MidWord: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "midword",
        abstract:
            "Report, for a floor, how many sensible mid-word continuations are kept and how many nonsense ones pass."
    )

    @Option(name: .long, help: "Which model to run: gemma3, gemma3Small, or a repository name.")
    var model = "gemma3"

    @Option(name: .long, help: "The floor to tally; defaults to the one the app uses.")
    var floor = Verification.plausibilityFloor

    @Flag(name: .long, help: "Also print a row per floor from -9 to -2.")
    var sweep = false

    @Flag(name: .long, help: "Print the score of every line.")
    var verbose = false

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
        var scored: [MidWordCalibration.Scored] = []
        for line in MidWordCalibration.lines() {
            let score = await scorer.logLikelihood(of: line.line, following: line.typed)
            scored.append(
                MidWordCalibration.Scored(
                    typed: line.typed, line: line.line, isSensible: line.isSensible, score: score))
            if verbose {
                let shown = score.map { String(format: "%8.3f", $0) } ?? "    none"
                let label = line.isSensible ? "sensible" : "nonsense"
                print("  \(shown)  \(label)  \(line.typed.debugDescription) -> \(line.line.debugDescription)")
            }
        }
        let result = MidWordCalibration.tally(scored, floor: floor)
        print(
            "floor \(floor) with \(chosen.shortName): kept \(result.sensibleKept) of \(result.sensibleTotal) sensible, "
                + "passed \(result.nonsensePassed) of \(result.nonsenseTotal) nonsense, \(result.unscored) unscored"
        )
        if sweep {
            print()
            print(
                MidWordCalibration.markdown(
                    scored, floors: stride(from: -9.0, through: -2.0, by: 0.5).map { $0 }))
        }
    }

    private static func model(named name: String) -> LocalModel? {
        switch name {
        case "gemma3": .gemma3
        case "gemma3Small": .gemma3Small
        default: LocalModel.named(name)
        }
    }
}
