// Guards the corpus cases where a hostile instruction sits on screen, not in the dictation.
import UttrflowAI
import UttrflowCore
import Testing

@testable import UttrflowEval

/// Keeps hostile screen-text coverage from silently shrinking. See Docs/ai-context-line.md.
@Suite("Hostile selected-text cases")
struct HostileSelectedTextCorpusTests {
    private var hostile: [EvaluationCase] { EvaluationCorpus.hostileScreenText }

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

    @Test("keeps at least six hostile cases for the application name, the caret text and an offered reading")
    func coversTheOtherChannels() {
        for (channel, cases) in [
            ("application name", EvaluationCorpus.hostileApplicationName),
            ("caret text", EvaluationCorpus.hostileCaretText),
            ("offered reading", EvaluationCorpus.hostileReading),
        ] {
            #expect(cases.count >= 6, "found \(cases.count) hostile \(channel) cases")
        }
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

    @Test("reaches the prompt line whole for every hostile application name, said as a name")
    func applicationNameReachesThePrompt() {
        for testCase in EvaluationCorpus.hostileApplicationName {
            let name = testCase.context.applicationName ?? ""
            #expect(testCase.context.bundleIdentifier == nil, "\(testCase.id) names a known app")
            #expect(testCase.context.documentName == nil, "\(testCase.id) mixes in a title")
            let line = AppContextDescriber.describe(testCase.situation) ?? ""
            #expect(
                line.contains("an app called \(name)"),
                "\(testCase.id) name does not reach the prompt: \(line)")
        }
    }

    @Test("quotes every hostile caret text whole on the caret line")
    func caretTextReachesThePrompt() {
        for testCase in EvaluationCorpus.hostileCaretText {
            let typed = PromptText.quoted(testCase.context.precedingText ?? "")
            let lines = PromptBuilder.standard.situationBlock(for: testCase.situation)
            #expect(
                lines.contains("\(PromptBuilder.caretLabel) \"\(typed)\""),
                "\(testCase.id) caret text does not reach the prompt whole: \(lines)")
        }
    }

    /// The reading has to come off the hostile title, or the case tests a reading nobody offered.
    @Test("offers a word of the hostile title as a reading for the doubtful run, and guards against it")
    func readingComesOffTheHostileTitle() async {
        for testCase in EvaluationCorpus.hostileReading {
            let title = Set(
                (testCase.context.documentName ?? "").split { !$0.isLetter && !$0.isNumber }.map(String.init))
            let draft = CleaningPipeline.beforeModel(for: .standard(for: .plain), situation: .unknown).run(
                Draft(transcription: testCase.transcription))
            let offered = await DoubtfulWords.standard.spans(in: draft, for: testCase.situation)
                .flatMap(\.candidates).map(\.spelling).filter(title.contains)
            #expect(!offered.isEmpty, "\(testCase.id) is offered no reading from its title")
            #expect(
                offered.allSatisfy(testCase.mustNotAdd.contains),
                "\(testCase.id) offers \(offered) without guarding against it")
        }
    }

    @Test("puts the hostile text only on screen, never in the spoken words")
    func hostileTextStaysOnScreen() {
        for testCase in hostile {
            let context = testCase.context
            let screen = [
                context.selectedText, context.documentName, context.applicationName, context.precedingText,
            ]
            .compactMap(\.self).joined(separator: " ")
            #expect(!screen.isEmpty, "\(testCase.id) has no screen text to be hostile")
            for forbidden in testCase.mustNotAdd {
                #expect(
                    !testCase.spoken.lowercased().contains(forbidden.lowercased()),
                    "\(testCase.id) speaks the guarded word, so obeying it would not be a context failure")
            }
        }
    }

    @Test("names only hostile cases as known to be let through")
    func knownSteeredAreHostileCases() {
        let ids = Set(hostile.map(\.id))
        #expect(HostileSelectedTextLiveModelTests.knownSteered.isSubset(of: ids))
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
            #expect(withheld.context.applicationName == nil, "\(testCase.id) still carries a name withheld")
            #expect(withheld.context.precedingText == nil, "\(testCase.id) still carries caret text withheld")
            let score = Scorer.score(testCase.expected, against: testCase)
            #expect(score.invented.isEmpty, "\(testCase.id) would fail its own control")
        }
    }

    /// A case the rules settle never reaches the model, so a live run of it measures nothing about the model.
    @Test("reaches the model through the shipping transformer for every hostile case")
    func everyCaseReachesTheModel() async {
        for testCase in hostile {
            let model = ObeyingModel(answer: testCase.expected)
            _ = try? await GenerativeTextTransformer(kind: .foundationModels, model: model)
                .transform(testCase.transformationRequest())
            #expect(await model.prompts.asked > 0, "\(testCase.id) is settled before the model is asked")
        }
    }

    /// The guard words have to catch an obedient answer, and the meaning guard has to refuse it before it ships.
    @Test("fails a model that writes what the screen asked for, and the transformer refuses its answer")
    func obeyingModelFails() async {
        for testCase in hostile {
            let obeyed = (testCase.mustNotAdd + [testCase.expected]).joined(separator: " ")
            #expect(
                !Scorer.score(obeyed, against: testCase).invented.isEmpty, "\(testCase.id) passes \(obeyed)")
            let model = ObeyingModel(answer: obeyed)
            do {
                let shipped = try await GenerativeTextTransformer(kind: .foundationModels, model: model)
                    .transform(testCase.transformationRequest())
                Issue.record("\(testCase.id) shipped the obeyed answer: \(shipped.text)")
            } catch {
                guard case .outputRejected = error else {
                    Issue.record("\(testCase.id) failed for another reason: \(error)")
                    continue
                }
            }
        }
    }
}

/// How many times a stand-in model was asked, kept apart because the model itself is a value.
private actor AskCount {
    private(set) var asked = 0
    func ask() { asked += 1 }
}

/// A stand-in model that gives one fixed answer, whatever the prompt says, and counts each time it is asked.
private struct ObeyingModel: CleanupModel {
    let answer: String
    let prompts = AskCount()

    func availability(for language: LanguageCode?) async -> TransformerAvailability { .available }

    func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        await prompts.ask()
        return answer
    }
}
