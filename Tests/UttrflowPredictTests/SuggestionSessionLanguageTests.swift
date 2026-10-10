import Testing

@testable import UttrflowPredict

@Suite("Suggestion language matches its context", .bug(id: 5337))
struct SuggestionSessionLanguageTests {
    @Test("A continuation in a different language is refused, while Hinglish stays available")
    func refusesForeignContinuationsInEnglishContext() throws {
        let typed = "Thanks for your message, "
        let context = PredictionContext(typed: typed, isProse: true)

        for continuation in [
            "ich melde mich morgen", "je vous répondrai demain", "te responderé mañana",
        ] {
            var session = SuggestionSession()
            let candidate = remembered(typed + continuation, count: 40)
            let update = try draw(
                &session, typing: typed, candidates: [candidate], context: context)
            #expect(update?.suggestion.accepting == nil)
        }

        var hinglish = SuggestionSession()
        let candidate = remembered(typed + "haan main kal aaunga", count: 40)
        let update = try draw(&hinglish, typing: typed, candidates: [candidate], context: context)
        #expect(update?.suggestion.accepting == candidate.text)
    }
}

@Suite("The language gate judges only what it can tell", .bug(id: 5337))
struct SuggestionLanguageTests {
    private let typed = "Thanks for your message, "

    @Test("An English continuation of English text continues")
    func sameLanguageContinues() {
        let context = PredictionContext(typed: typed, isProse: true)
        #expect(SuggestionLanguage.continues(typed + "I will reply tomorrow", in: context))
    }

    @Test("A continuation too short to judge is never refused")
    func shortRunsAreNotJudged() {
        #expect(
            SuggestionLanguage.continues(typed + "danke", in: PredictionContext(typed: typed, isProse: true)))
        #expect(
            SuggestionLanguage.continues(
                "Hi ich melde mich morgen", in: PredictionContext(typed: "Hi ", isProse: true)))
    }

    @Test("A command line has no language to hold a continuation to")
    func commandLinesAreNotJudged() {
        #expect(
            SuggestionLanguage.continues(typed + "ich melde mich morgen", in: PredictionContext(typed: typed))
        )
    }

    @Test("A model line in another language is not drawn")
    func generatedForeignLineIsDropped() {
        var session = SuggestionSession()
        let field = Surface(bundleIdentifier: "com.example.chat", role: "AXTextArea")
        let turn = session.turn(in: field, at: PredictionContext(typed: typed, isProse: true))
        guard case .query(let query) = turn.step else {
            Issue.record("expected a query")
            return
        }
        let update = session.resolveSure(
            [typed + "ich melde mich morgen"], for: query, elapsedMilliseconds: 0)
        #expect(update?.suggestion.accepting == nil)
    }
}
