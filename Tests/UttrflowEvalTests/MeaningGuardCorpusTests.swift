import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowEval

@Suite("Meaning guard over the cleanup corpus")
struct MeaningGuardCorpusTests {
    @Test("expected tidy-ups do not relocate a negation")
    func expectedTidyUpsKeepNegationPlacement() {
        let guarder = MeaningPreservationGuard()
        for sample in EvaluationCorpus.all {
            let draft = CleaningPipeline.standard.run(Draft(keepingLineBreaks: sample.spoken))
            if case .rejected(_, let kind) = guarder.verdict(draft: draft, rewritten: sample.expected) {
                #expect(kind != .negationMoved, "\(sample.id) should not move a negation")
            }
        }
    }

    @Test("the cleanup corpus keeps Indian grouping as written")
    func corpusKeepsIndianGrouping() {
        for sample in EvaluationCorpus.all where sample.id.hasPrefix("indian-grouping-") {
            #expect(
                MeaningPreservationGuard.changedIndianGrouping(
                    original: sample.spoken, rewritten: sample.expected
                ) == nil,
                "\(sample.id) changes its numeric grouping"
            )
        }
    }

    @Test("as-spoken chat examples keep dialect verb forms")
    func asSpokenExamplesKeepDialectVerbForms() {
        let guarder = MeaningPreservationGuard()
        let examples = [
            ("we was just talking about you", "We was just talking about you"),
            ("they was at the shop", "They was at the shop"),
            ("i seen it yesterday", "I seen it yesterday"),
            ("he come by yesterday", "He come by yesterday"),
        ]
        #expect(examples.count == 4)
        for (spoken, expected) in examples {
            #expect(
                guarder.verdict(
                    draft: Draft(text: spoken), rewritten: expected,
                    grammar: DestinationFormatter.standard(for: .messaging).grammar
                ).isAccepted,
                "\(spoken) should preserve its spoken form"
            )
        }
    }

    @Test(
        "as-spoken destinations refuse a small word a second-language sentence did not say",
        arguments: [
            ("i need to buy new laptop", "I need to buy a new laptop."),
            ("he went to doctor yesterday", "He went to the doctor yesterday."),
            ("she is expert of databases", "She is an expert in databases."),
            ("he is married with her sister", "He is married to her sister."),
            ("do not be angry on him", "Do not be angry with him."),
            ("he is sick since many days", "He is sick for many days."),
            ("i will do it in the weekend", "I will do it at the weekend."),
            ("we are waiting the bus", "We are waiting for the bus."),
            ("she not like cold coffee", "She does not like cold coffee."),
            ("can you tell me where is the station", "Can you tell me where the station is?"),
        ]
    )
    func asSpokenRefusesAddedSmallWords(spoken: String, repaired: String) {
        let messaging = DestinationFormatter.standard(for: .messaging).grammar
        let verdict = MeaningPreservationGuard().verdict(
            draft: Draft(text: spoken), rewritten: repaired, grammar: messaging)
        #expect(!verdict.isAccepted, "\(spoken) → \(repaired)")
    }

    @Test("as-spoken destinations accept every second-language case written as spoken")
    func asSpokenAcceptsSecondLanguageCases() {
        let guarder = MeaningPreservationGuard()
        #expect(EvaluationCorpus.secondLanguage.count == 40)
        for sample in EvaluationCorpus.secondLanguage {
            let verdict = guarder.verdict(
                draft: Draft(text: sample.spoken), rewritten: sample.expected,
                grammar: DestinationFormatter.standard(for: sample.destination).grammar)
            #expect(verdict.isAccepted, "\(sample.id): \(verdict)")
        }
    }
}
