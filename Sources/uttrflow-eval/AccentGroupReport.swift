// The `accent-groups` command: per-group rates over a locally scored real-speaker slice, with speaker-resampled intervals.
import ArgumentParser
private import Foundation
private import UttrflowEval

/// Reads per-clip counts from a locally downloaded slice and prints the per-group report.
struct AccentGroupReport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "accent-groups",
        abstract:
            "Report error and false-override rates per accent group, resampling speakers, from a local counts table."
    )

    @Option(
        name: .long,
        help:
            "Tab-separated rows: speaker, group, label (verified or self-described), errors, words, decisions, false overrides."
    )
    var rows: String

    @Option(name: .long, help: "The false-override rate each row must be able to bound.")
    var decisionBound = 0.001

    func run() throws {
        guard let data = FileManager.default.contents(atPath: rows),
            let text = String(data: data, encoding: .utf8)
        else { throw ValidationError("cannot read the counts table at \(rows)") }
        var clips: [SpeakerClip] = []
        for (number, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 7, let label = AccentLabelKind(rawValue: fields[2]),
                let errors = Int(fields[3]), let words = Int(fields[4]), let decisions = Int(fields[5]),
                let overrides = Int(fields[6])
            else { throw ValidationError("line \(number + 1) is not a counts row") }
            clips.append(
                SpeakerClip(
                    speaker: fields[0], group: fields[1], label: label, errors: errors, words: words,
                    decisions: decisions, falseOverrides: overrides))
        }
        SpeakerGroupReport(clips: clips, decisionBound: decisionBound).lines.forEach { print($0) }
    }
}
