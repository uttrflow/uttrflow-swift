// Holds the command reader to the recorded recogniser output for every Markdown command phrase on synthesised speech.
import Foundation
import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

@Suite("Command phrases heard on synthesised audio")
struct CommandAudioRecallTests {
    /// What the recogniser wrote for each take, as `uttrflow-eval command-recall --record` last wrote it.
    static let takes: [CommandTake] = {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(
            path: "Golden/command-audio.tsv")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4, let snr = Double(fields[2]) else { return nil }
            return CommandTake(commandID: fields[0], voice: fields[1], snr: snr, heard: fields[3])
        }
    }()

    @Test("records at least 10 takes of every Markdown command, clean and noisy, in several accents")
    func everyCommandIsHeard() {
        let takes = Self.takes
        for row in SpokenCommands.markdown {
            let mine = takes.filter { $0.commandID == row.id }
            #expect(mine.count >= 10, "\(row.id)")
            #expect(Set(mine.map(\.voice)).count >= 3, "\(row.id)")
            #expect(mine.contains { $0.snr.isInfinite } && mine.contains { !$0.snr.isInfinite }, "\(row.id)")
        }
    }

    @Test("the shipped reader keeps the recorded recall and adds no misfire")
    func shippedReaderHoldsTheGate() {
        let report = CommandAudioReport(takes: Self.takes, reads: MarkdownCommand.edit(for:on:))
        #expect(report.recall >= CommandAudioReport.recallFloor)
        #expect(report.misfires.count <= CommandAudioReport.misfireCeiling, "\(report.misfires)")
        #expect(report.passesGate)
    }

    @Test("a reader that takes only the bare phrase, not the recogniser's written forms, fails the gate")
    func weakenedReaderFailsTheGate() {
        let bare: (String, AppContext) -> String? = { heard, target in
            SpokenCommands.markdown.contains { $0.words.joined(separator: " ") == heard }
                ? MarkdownCommand.edit(for: heard, on: target) : nil
        }
        let report = CommandAudioReport(takes: Self.takes, reads: bare)
        #expect(report.recall < CommandAudioReport.recallFloor)
        #expect(!report.passesGate)
    }

    @Test("a take heard as another command is a misfire, and one heard as nothing is only a miss")
    func misfireAndMissAreTold() {
        let takes = [
            CommandTake(commandID: "markdown.bold", voice: "v", snr: .infinity, heard: "Bold."),
            CommandTake(commandID: "markdown.bold", voice: "v", snr: 10, heard: "Italic."),
            CommandTake(commandID: "markdown.bold", voice: "w", snr: 10, heard: "Old."),
            CommandTake(commandID: "markdown.heading-1", voice: "w", snr: .infinity, heard: "Heading 1."),
        ]
        let report = CommandAudioReport(takes: takes, reads: MarkdownCommand.edit(for:on:))
        #expect(report.rows.map(\.hits) == [1, 1])
        #expect(report.misfires == [takes[1]])
        #expect(report.missed == [takes[1], takes[2]])
        #expect(report.recall(where: { $0.snr == 10 }) == 0)
        #expect(report.recall(where: { $0.voice == "w" }) == 0.5)
        #expect(report.recall == 0.5)
    }
}
