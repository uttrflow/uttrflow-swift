// The `final-piece` command: how long the last piece is at key-up under the shipped windowing.
import ArgumentParser
private import Foundation
private import UttrflowEval

/// Runs word-aligned speech through the shipped windowing and reports the last piece's length at key-up.
struct FinalPieceProbe: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "final-piece",
        abstract: "Measure the length of the last piece at key-up on word-aligned speech."
    )

    /// Tab-separated lines of group, speaker, utterance, word, start and end seconds; synthetic speakers when absent.
    @Option(
        name: .long,
        help: "A word-alignment file: group, speaker, utterance, word, start, end, tab-separated.")
    var alignments: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Dictation lengths in seconds.")
    var lengths: [Double] = [20, 30, 60, 90, 120]

    @Option(name: .long, help: "Seconds of silence between joined utterances.")
    var gap = 0.3

    @Option(name: .long, parsing: .upToNextOption, help: "Final-piece lengths to report the share above.")
    var bounds: [Double] = [5, 10]

    func validate() throws {
        if lengths.isEmpty || lengths.contains(where: { $0 <= 0 }) {
            throw ValidationError("--lengths must be positive.")
        }
        if gap < 0 { throw ValidationError("--gap must not be negative.") }
    }

    func run() throws {
        let groups = try alignments.map(load) ?? Self.synthetic()
        let boundHeads = bounds.map { "Over \(format($0)) s" }.joined(separator: " | ")
        print("| Group | Dictations | p50 s | p95 s | \(boundHeads) |")
        print("|---|---|---|---|" + bounds.map { _ in "---|" }.joined())
        for (group, speakers) in groups.sorted(by: { $0.key < $1.key }) {
            var pieces: [Double] = []
            for timeline in speakers {
                for seconds in lengths {
                    guard let last = timeline.last, last.end >= seconds,
                        let keyUp = FinalPiece.keyUp(in: timeline, after: seconds)
                    else { continue }
                    pieces.append(FinalPiece.length(of: timeline, keyUp: keyUp))
                }
            }
            guard let median = FinalPiece.percentile(pieces, 0.5),
                let high = FinalPiece.percentile(pieces, 0.95)
            else { continue }
            let shares = bounds.map { bound in
                let over = Double(pieces.filter { $0 > bound }.count) / Double(pieces.count)
                return "\(Int((over * 100).rounded()))%"
            }
            print(
                "| \(group) | \(pieces.count) | \(format(median)) | \(format(high)) | "
                    + shares.joined(separator: " | ") + " |")
        }
    }

    private func format(_ value: Double) -> String { String(format: "%.1f", value) }

    /// Each speaker's utterances joined into one timeline, grouped by the file's first column.
    private func load(_ path: String) throws -> [String: [[AlignedWord]]] {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        var words: [String: [String: [String: [AlignedWord]]]] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\t").map(String.init)
            guard fields.count == 6, let start = Double(fields[4]), let end = Double(fields[5]) else {
                continue
            }
            words[fields[0], default: [:]][fields[1], default: [:]][fields[2], default: []].append(
                AlignedWord(word: fields[3], start: start, end: end))
        }
        return words.mapValues { speakers in
            speakers.sorted { $0.key < $1.key }.map { _, utterances in
                FinalPiece.concatenate(utterances.sorted { $0.key < $1.key }.map(\.value), gap: gap)
            }
        }
    }

    /// Speakers whose sentence pauses fall under, and over, the shipped sentence pause.
    private static func synthetic() -> [String: [[AlignedWord]]] {
        let seeds = UInt64(1)...UInt64(20)
        return [
            "synthetic, pauses 0.3-0.75 s": seeds.map {
                FinalPiece.syntheticSpeaker(seconds: 125, pauses: 0.3...0.75, seed: $0)
            },
            "synthetic, pauses 0.9-1.4 s": seeds.map {
                FinalPiece.syntheticSpeaker(seconds: 125, pauses: 0.9...1.4, seed: $0)
            },
        ]
    }
}
