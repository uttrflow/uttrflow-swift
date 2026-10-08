// The `accuracy-report` command: a release's public accuracy report, from the committed baseline.
import ArgumentParser
private import Foundation
private import UttrflowEval

/// Writes the report for one release and records its baseline in the history the next release compares with.
struct AccuracyReportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "accuracy-report",
        abstract:
            "Write a release's accuracy report from the committed baseline and record it in the history."
    )

    @Option(name: .long, help: "The release version the report is for.")
    var version: String

    @Option(name: .long, help: "The committed baseline to report.")
    var baseline = "Scripts/accuracy_baseline.json"

    @Option(name: .long, help: "The per-release history, read for the previous release and given this one.")
    var history = "Docs/accuracy-history.json"

    @Option(name: .long, help: "Where to write the report; defaults to Docs/accuracy-reports/<version>.md.")
    var output: String?

    func run() throws {
        let measured = try AccuracyBaseline.read(from: URL(fileURLWithPath: baseline))
        let historyURL = URL(fileURLWithPath: history)
        var releases = try AccuracyHistory.read(from: historyURL)
        let report = AccuracyReport(version: version, baseline: measured, history: releases)
        let reportURL = URL(fileURLWithPath: output ?? "Docs/accuracy-reports/\(version).md")
        try FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try report.markdown.write(to: reportURL, atomically: true, encoding: .utf8)
        releases.record(AccuracyHistory.Release(version: version, baseline: measured))
        try releases.write(to: historyURL)
        print("Wrote \(reportURL.path) and recorded \(version) in \(history).")
    }
}
