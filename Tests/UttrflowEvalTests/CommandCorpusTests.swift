// Guards the command corpus and its gate: zero false executions, full recall, and a weakened guard turns it red.
import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

@Suite("Command-key utterances and dictated mentions: recall and false execution")
struct CommandCorpusTests {
    private let cases = EvaluationCorpus.commandCases
    private let mentions = EvaluationCorpus.commandMentions

    /// Dictation that writes the words as said, for the tests about the command key alone.
    private let verbatim: (EvaluationCase) -> String = \.spoken

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

    @Test("holds 10 dictated mentions of every Markdown command, each guarding the command's mark")
    func everyCommandMentioned() throws {
        let rows = Dictionary(uniqueKeysWithValues: SpokenCommands.markdown.map { ($0.id, $0) })
        let named = mentions.map(EvaluationCorpus.commandID(mentionedIn:))
        for id in rows.keys { #expect(named.count { $0 == id } == 10, "\(id)") }
        for (mention, id) in zip(mentions, named) {
            let row = try #require(id.flatMap { rows[$0] }, "\(mention.id) names no command")
            #expect(mention.mustNotAdd == [row.text.trimmingCharacters(in: .whitespacesAndNewlines)])
            #expect(CaretStructure.isMarkdown(documentName: mention.context.documentName))
            #expect(Scorer.score(mention.expected, against: mention).invented.isEmpty, "\(mention.id)")
        }
    }

    @Test("the rules dictation writes every mention as prose, so no command runs on it")
    func shippedDictationPassesTheGate() async throws {
        var written: [String: String] = [:]
        for mention in mentions {
            written[mention.id] = try await RuleBasedTransformer().transform(mention.transformationRequest())
                .text
        }
        let report = CommandReport(reads: MarkdownCommand.edit(for:on:)) { written[$0.id] ?? "" }
        #expect(report.mentionExecutions.isEmpty, "\(report.mentionExecutions.map(\.id))")
        #expect(report.rows.allSatisfy { $0.mentioned == 10 && $0.mentionRuns == 0 })
        #expect(report.passesGate)
    }

    @Test("dictation that runs a command it hears anywhere in prose writes the mark, and the gate fails")
    func dictationThatObeysMentionsFailsTheGate() {
        let obeys: (EvaluationCase) -> String = { mention in
            let row = SpokenCommands.markdown.first {
                $0.id == EvaluationCorpus.commandID(mentionedIn: mention)
            }
            return row.map { $0.text + mention.spoken + $0.text } ?? mention.spoken
        }
        let report = CommandReport(reads: MarkdownCommand.edit(for:on:), dictates: obeys)
        #expect(!report.passesGate)
        #expect(report.mentionExecutions.count == mentions.count)
        #expect(report.falseExecutions.isEmpty)
    }

    @Test("the shipped reader runs every command case and no content case")
    func shippedReaderPassesTheGate() {
        let report = CommandReport(reads: MarkdownCommand.edit(for:on:), dictates: verbatim)
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
        let report = CommandReport(reads: loose, dictates: verbatim)
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
        let report = CommandReport(reads: blind, dictates: verbatim)
        #expect(!report.passesGate)
        #expect(Set(report.falseRunsByDocument.keys) == Set(EvaluationCorpus.otherDocuments))
    }
}
