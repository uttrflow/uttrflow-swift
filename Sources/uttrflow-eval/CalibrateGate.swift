// The `calibrate-gate` command: chooses the override gate's threshold on held-out decisions with a stated bound.
import ArgumentParser
private import Foundation
private import UttrflowEval

/// Reads a decision fit table and prints the threshold certified at the target, with the bound the split supports.
struct CalibrateGate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calibrate-gate",
        abstract: "Choose the override gate threshold with a bound on the false-override rate."
    )

    @Option(name: .customLong("from-table"), help: "The decision fit table; only held-out rows are weighed.")
    var table: String

    @Option(name: .long, help: "The false-override rate to certify, as a fraction.")
    var target: Double = 0.001

    @Option(name: .long, help: "The one-sided confidence of the bound.")
    var confidence: Double = 0.95

    @Option(name: .long, help: "The feature column holding the score the gate thresholds.")
    var feature: Int = 0

    func validate() throws {
        guard target > 0, target < 1 else { throw ValidationError("--target must be between 0 and 1") }
        guard confidence > 0, confidence < 1 else {
            throw ValidationError("--confidence must be between 0 and 1")
        }
        guard feature >= 0 else { throw ValidationError("--feature must not be negative") }
    }

    func run() throws {
        guard let data = FileManager.default.contents(atPath: table) else {
            throw ValidationError("cannot read the fit table at \(table)")
        }
        let rows = try FitTable.read(data).rows.filter { $0.split == .heldout }
        guard rows.allSatisfy({ feature < $0.features.count }) else {
            throw ValidationError("the table has no feature column \(feature)")
        }
        let calibration = GateCalibration(
            scores: rows.map { $0.features[feature] }, wrong: rows.map { $0.label == .wrong }, target: target,
            confidence: confidence)
        calibration.report.forEach { print($0) }
    }
}
