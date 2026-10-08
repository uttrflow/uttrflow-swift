// Guards the corpus cases where a hostile instruction sits on screen, not in the dictation.
import UttrflowAI
import UttrflowCore
import Testing

@testable import UttrflowEval

/// Keeps hostile screen-text coverage from silently shrinking. See Docs/ai-context-line.md.
@Suite("Hostile selected-text cases")
struct HostileSelectedTextCorpusTests {
    private var hostile: [EvaluationCase] {
        EvaluationCorpus.hostileSelectedText + EvaluationCorpus.hostileWindowTitle
    }

    @Test("keeps at least one case per documented hostile screen instruction")
    func coversEveryDocumentedInstruction() {
        #expect(
            EvaluationCorpus.hostileSelectedText.count >= 3,
            "found \(EvaluationCorpus.hostileSelectedText.count) hostile-selected-text cases")
    }

    @Test("keeps at least six hostile window-title cases")
    func coversTheWindowTitleChannel() {
        #expect(
            EvaluationCorpus.hostileWindowTitle.count >= 6,
            "found \(EvaluationCorpus.hostileWindowTitle.count) hostile window-title cases")
    }

    /// A title cut short by the describer would test less than it claims.
    @Test("reaches the prompt line whole for every hostile window title")
    func windowTitleReachesThePrompt() {
        for testCase in EvaluationCorpus.hostileWindowTitle {
            let title = testCase.context.documentName ?? ""
            #expect(testCase.context.selectedText == nil, "\(testCase.id) mixes in a selection")
            let line = AppContextDescriber.describe(testCase.situation) ?? ""
            #expect(line.contains(title), "\(testCase.id) title does not reach the prompt: \(line)")
        }
    }

    @Test("puts the hostile text only on screen, never in the spoken words")
    func hostileTextStaysOnScreen() {
        for testCase in hostile {
            let screen = (testCase.context.selectedText ?? "") + (testCase.context.documentName ?? "")
            #expect(!screen.isEmpty, "\(testCase.id) has no screen text to be hostile")
            for forbidden in testCase.mustNotAdd {
                #expect(
                    !testCase.spoken.lowercased().contains(forbidden.lowercased()),
                    "\(testCase.id) speaks the guarded word, so obeying it would not be a context failure")
            }
        }
    }

    @Test("guards against the output obeying, answering, or copying the screen text")
    func guardsAreNotEmpty() {
        for testCase in hostile {
            #expect(!testCase.mustNotAdd.isEmpty, "\(testCase.id) has nothing to catch a hostile answer")
        }
    }

    /// A reference that trips its own guards would fail every model on a fault in the corpus.
    @Test("accepts each reference answer as a perfect answer to its own case")
    func referencesAreSelfConsistent() {
        for testCase in hostile {
            let score = Scorer.score(testCase.expected, against: testCase)
            #expect(score.similarity == 1, "\(testCase.id) does not match itself")
            #expect(score.invented.isEmpty, "\(testCase.id) breaks its own guard: \(score.invented)")
        }
    }

    /// Withholding context removes the hostile text along with everything else, so the control must be clean.
    @Test("has a context-withheld control that needs no guard to pass")
    func controlWithheldContextIsClean() {
        for testCase in hostile {
            let withheld = testCase.transformationRequest(withholdingContext: true)
            #expect(withheld.context.selectedText == nil, "\(testCase.id) still carries a selection withheld")
            #expect(withheld.context.documentName == nil, "\(testCase.id) still carries a title withheld")
            let score = Scorer.score(testCase.expected, against: testCase)
            #expect(score.invented.isEmpty, "\(testCase.id) would fail its own control")
        }
    }
}
