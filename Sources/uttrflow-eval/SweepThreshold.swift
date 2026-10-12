// The `sweep` command: chooses one threshold from a fit table and writes the record of what it tried.
import ArgumentParser
private import Foundation
private import UttrflowEval

/// Sweeps a named threshold over a fit table feature and writes one JSON record with the grid, the neighbours and the test score.
struct SweepThreshold: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sweep",
        abstract: "Choose a threshold on the fit and calibration sides and keep the evidence."
    )

    @Option(name: .customLong("from-table"), help: "The fit table to read.")
    var table: String

    @Option(name: .long, help: "The name of the threshold, recorded with the result.")
    var parameter: String

    @Option(name: .long, help: "The feature column the threshold applies to.")
    var feature: Int = 0

    @Option(name: .long, help: "Flag a row at or below the threshold (below) or at or above it (above).")
    var flags: String = "below"

    @Option(name: .long, help: "The grid, as comma-separated values.")
    var grid: String

    @Option(
        name: .customLong("false-flag-bound"), help: "The most right rows the flag may catch, as a fraction.")
    var falseFlagBound: Double = 0.05

    @Option(name: .long, help: "The seed that splits held-out rows into calibration and test.")
    var seed: String = "0"

    @Option(
        name: .customLong("margin-steps"), help: "Grid steps to move off a cliff toward its flatter side.")
    var marginSteps: Int = 0

    @Option(
        name: .customLong("cliff-tolerance"), help: "How much worse a neighbour may score before a cliff.")
    var cliffTolerance: Double = 0.05

    @Option(name: .long, help: "The engine identity the table was decoded under, recorded as given.")
    var engine: String = ""

    @Option(name: .long, help: "Where to write the record.")
    var record: String?

    func validate() throws {
        guard ["below", "above"].contains(flags) else { throw ValidationError("--flags is below or above") }
        guard falseFlagBound >= 0, falseFlagBound <= 1 else {
            throw ValidationError("--false-flag-bound must be between 0 and 1")
        }
        guard feature >= 0, marginSteps >= 0, cliffTolerance >= 0 else {
            throw ValidationError("--feature, --margin-steps and --cliff-tolerance must not be negative")
        }
        guard cliffTolerance.isFinite else {
            throw ValidationError("--cliff-tolerance must be finite")
        }
        guard values.count >= 2, values.allSatisfy(\.isFinite) else {
            throw ValidationError("--grid needs at least two numbers")
        }
    }

    var values: [Double] {
        grid.split(separator: ",", omittingEmptySubsequences: false).map {
            Double($0.trimmingCharacters(in: .whitespaces)) ?? .nan
        }
    }

    func run() throws {
        guard let data = FileManager.default.contents(atPath: table) else {
            throw ValidationError("cannot read the fit table at \(table)")
        }
        let request = ThresholdSweep.Request(
            parameter: parameter, feature: feature, direction: flags == "below" ? .atOrBelow : .atOrAbove,
            grid: values, falseFlagBound: falseFlagBound, seed: seed, cliffTolerance: cliffTolerance,
            marginSteps: marginSteps, engine: engine)
        let sweep = try ThresholdSweep(table: FitTable.read(data), tableData: data, request: request)
        sweep.report.forEach { print($0) }
        if let record { try sweep.encoded().write(to: URL(fileURLWithPath: record)) }
        if sweep.record.chosen == nil { throw ExitCode.failure }
    }
}
