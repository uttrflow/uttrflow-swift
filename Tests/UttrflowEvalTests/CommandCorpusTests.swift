// Guards the command-key corpus and its gate: zero false executions, full recall, and a weakened reader turns it red.
import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

@Suite("Command-key utterances: recall and false execution")
struct CommandCorpusTests {
    private let cases = EvaluationCorpus.commandCases

    @Test("holds at least 10 cases that must run and 10 that must not for every Markdown command")
    func everyCommandMeasured() {
        let ids = Set(SpokenCommands.markdown.map(\.id))
        #expect(Set(cases.map(\.commandID)) == ids)
        for id in ids {
            let mine = cases.filter { $0.commandID == id }
            #expect(mine.count(where: \.shouldRun) >= 10, "\(id)")
            #expect(mine.count { !$0.shouldRun } >= 10, "\(id)")
        }
        #expect(Set(cases.map(\.kind)) == Set(CommandCaseKind.allCases))
    }

    @Test("the shipped reader runs every command case and no content case")
    func shippedReaderPassesTheGate() {
        let report = CommandReport(reads: MarkdownCommand.edit(for:on:))
        #expect(report.falseExecutions.isEmpty, "\(report.falseExecutions.map(\.utterance))")
        #expect(report.missed.isEmpty, "\(report.missed.map(\.utterance))")
        #expect(report.passesGate)
    }

    @Test("a reader that runs on any utterance containing the phrase executes content, and the gate fails")
    func weakenedReaderFailsTheGate() {
        let loose: (String, AppContext) -> String? = { utterance, target in
            let phrases = SpokenCommands.markdown.map { $0.words.joined(separator: " ") }
            let lowered = utterance.lowercased()
            guard let phrase = phrases.first(where: lowered.contains) else { return nil }
            return MarkdownCommand.edit(for: phrase, on: target)
        }
        let report = CommandReport(reads: loose)
        #expect(!report.passesGate)
        #expect(report.falseExecutions.allSatisfy { $0.kind == .embedded })
        #expect(report.rows.allSatisfy { $0.falseRuns > 0 })
    }

    @Test("a reader that ignores the document runs where Markdown does not render, by document")
    func documentBlindReaderFailsTheGate() {
        let blind: (String, AppContext) -> String? = { utterance, target in
            MarkdownCommand.edit(
                for: utterance,
                on: AppContext(
                    documentName: "notes.md", selectedText: target.selectedText,
                    precedingText: target.precedingText))
        }
        let report = CommandReport(reads: blind)
        #expect(!report.passesGate)
        #expect(Set(report.falseRunsByDocument.keys) == Set(EvaluationCorpus.otherDocuments))
    }
}
