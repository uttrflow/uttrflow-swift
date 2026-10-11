// The `fit` command: rebuilds a fitted artifact from its committed text-free table, with no audio and no network.
import ArgumentParser
private import Foundation
private import UttrflowAI
private import UttrflowEval

/// Reads a fit table, checks its schema and the reranker's data floor, fits the linear scorer and prints the weights digest.
struct FitFromTable: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fit",
        abstract:
            "Reproduce a fitted scorer from a committed fit table and print its weights digest; refuses a table below the data floor."
    )

    @Option(name: .customLong("from-table"), help: "The fit table to read.")
    var table: String

    @Option(name: .long, help: "The committed weights digest; exits 1 when the fit does not reproduce it.")
    var expect: String?

    @Option(
        name: .customLong("span-golden"),
        help: "The span feature golden file, re-checked before any fit.")
    var spanGolden = "Tests/UttrflowEvalTests/Golden/span-features.json"

    func run() throws {
        try checkSpanFeatures()
        guard let data = FileManager.default.contents(atPath: table) else {
            throw ValidationError("cannot read the fit table at \(table)")
        }
        let read = try FitTable.read(data)
        try read.requireFeatureSpec(SpanFeatures.specVersion)
        let layer = FittedLayer.spanReranker
        print("excluded reader-deviation spans: \(read.excludedSpans.map(String.init) ?? "not recorded")")
        for cell in read.cellCounts {
            print(
                "\(cell.split.rawValue) \(cell.language.rawValue): \(cell.right) right, \(cell.wrong) wrong")
        }
        let shortfalls = read.shortfalls(for: layer)
        guard shortfalls.isEmpty else {
            print("below the \(layer.rawValue) floor in Docs/dictation-quality.md; not fitted:")
            for shortfall in shortfalls { print("  \(shortfall)") }
            throw ExitCode.failure
        }
        let digest = read.fitLinearScorer().digest
        print(digest)
        if let expect, expect != digest {
            print("does not reproduce \(expect)")
            throw ExitCode.failure
        }
    }

    /// Refuses to fit when the golden file no longer matches the extractor this build compiled.
    private func checkSpanFeatures() throws {
        guard let data = FileManager.default.contents(atPath: spanGolden) else {
            throw ValidationError("cannot read the span feature golden file at \(spanGolden)")
        }
        let disagreements = try SpanFeatureGolden.read(data).disagreements()
        guard disagreements.isEmpty else {
            for line in disagreements { print(line) }
            throw ValidationError("the golden file and the compiled span features disagree; not fitted")
        }
    }
}
