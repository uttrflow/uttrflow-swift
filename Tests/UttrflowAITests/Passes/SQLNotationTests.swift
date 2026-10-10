import Foundation
import Testing
import UttrflowCore
import UttrflowEval

@testable import UttrflowAI

/// A statement dictated into a query editor is written as SQL notation, converting only what was said.
@Suite("SQL notation in a query editor")
struct SQLNotationTests {
    /// The corpus's spoken statements, each with the one statement it must be written as.
    static let statements = EvaluationCorpus.all.filter { $0.id.hasPrefix("sql-statement-") }

    /// The passes before the model for a case's caret, which is where notation is written.
    private static func written(_ testCase: EvaluationCase) -> String {
        let app = testCase.context
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .sqlEditor)
        let pipeline = CleaningPipeline.beforeModel(for: .standard(for: .sqlEditor), situation: situation)
        return pipeline.run(Draft(text: testCase.spoken)).text
    }

    /// The lower-cased runs of letters in a text, which is what an added keyword, clause or alias would show in.
    private static func letterWords(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter }.map(String.init)
    }

    @Test("writes all forty statements exactly")
    func writesEveryStatement() {
        #expect(Self.statements.count == 40)
        for testCase in Self.statements {
            #expect(Self.written(testCase) == testCase.expected, "\(testCase.id)")
        }
    }

    @Test("adds no word and no unsourced mark to any statement")
    func convertsNotationOnly() {
        for testCase in Self.statements {
            let written = Self.written(testCase)
            let said = Set(Self.letterWords(testCase.spoken))
            let added = Self.letterWords(written).filter { !said.contains($0) }
            #expect(added.isEmpty, "\(testCase.id) adds \(added)")
            let alignment = NotationAlignment.align(spoken: testCase.spoken, written: written)
            #expect(alignment.unsourced.isEmpty, "\(testCase.id) invents \(alignment.unsourced)")
            #expect(alignment.dropped.isEmpty, "\(testCase.id) drops \(alignment.dropped)")
        }
    }

    @Test("leaves the corpus's prose in a query editor as spoken")
    func abstainsOnProse() {
        let prose = EvaluationCorpus.abstention.filter { $0.destination == .sqlEditor }
        #expect(prose.count >= 20)
        for testCase in prose {
            #expect(Self.written(testCase) == testCase.spoken, "\(testCase.id)")
        }
    }

    @Test("reads a statement only where the speech opens one, outside a comment or string")
    func statementEvidence() {
        let screen = NotationEvidence.applicability(destination: .sqlEditor, region: .code)
        #expect(
            NotationEvidence.applicability(destination: .sqlEditor, opening: "select", given: screen)
                == .evidenced(confidence: 1, by: [.queryStatement]))
        #expect(
            NotationEvidence.applicability(destination: .sqlEditor, opening: "where", given: screen)
                == .noEvidence)
        for region in [CaretStructure.Region.comment, .string, .prose] {
            let ruledOut = NotationEvidence.applicability(destination: .sqlEditor, region: region)
            #expect(ruledOut == .ruledOut(by: .caretInProse))
            #expect(
                NotationEvidence.applicability(destination: .sqlEditor, opening: "select", given: ruledOut)
                    == ruledOut)
        }
        #expect(
            NotationEvidence.applicability(destination: .codeEditor, opening: "select", given: .noEvidence)
                == .noEvidence)
    }

    @Test("converts a statement's notation in under five milliseconds a case")
    func latency() {
        let pass = CodeEditorCommandsPass(destination: .sqlEditor, evidence: .noEvidence)
        let drafts = Self.statements.map { Draft(text: $0.spoken) }
        let elapsed = ContinuousClock().measure {
            for draft in drafts { _ = pass.apply(draft) }
        }
        #expect(elapsed / drafts.count < .milliseconds(5))
    }
}
