import Testing

@testable import UttrflowPredict

/// A chat composer, where romanised Hinglish and Devanagari are both typed.
private let composer = Surface(bundleIdentifier: "com.example.chat", role: "AXTextArea")

/// The query a turn asked for, or a failure saying it asked nothing.
private func asked(_ turn: SuggestionTurn) throws -> SuggestionQuery {
    guard case .query(let query) = turn.step else {
        Issue.record("expected a query")
        throw CancellationError()
    }
    return query
}

@Suite("Suggestions write only the Latin alphabet")
struct SuggestionSessionScriptTests {
    @Test(
        "A line holding another script asks neither the store nor the model, and says why.",
        arguments: ["नहीं ज", "ok नहीं", "你好", "abc ०"])
    func nonLatinLinesAreQuiet(typed: String) {
        var session = SuggestionSession()
        let turn = session.turn(in: composer, at: PredictionContext(typed: typed))
        #expect(turn.step == .settled(.quiet(because: .nonLatinLine)))
    }

    @Test("Romanised Hinglish and accented Latin still ask the store.", arguments: ["haan th", "café au"])
    func latinLinesAsk(typed: String) throws {
        var session = SuggestionSession()
        #expect(try asked(session.turn(in: composer, at: PredictionContext(typed: typed))).typed == typed)
    }

    @Test("A remembered line the person typed in another script is never offered back.")
    func rememberedNonLatinIsNotOffered() throws {
        var session = SuggestionSession()
        let alone = try draw(
            &session, typing: "ok", candidates: [remembered("ok नहीं", count: 40)], in: composer)
        #expect(alone?.suggestion.accepting == nil)
        var other = SuggestionSession()
        let beside = try draw(
            &other, typing: "ok",
            candidates: [remembered("ok नहीं", count: 40), remembered("ok theek hai", count: 40)], in: composer)
        #expect(beside?.suggestion == .certain("ok theek hai"))
    }

    @Test("A candidate the gates hand back in another script is not drawn.")
    func verifiedNonLatinIsNotDrawn() throws {
        var session = SuggestionSession()
        let query = try asked(session.turn(in: composer, at: PredictionContext(typed: "ok")))
        let request = VerificationRequest(
            surface: composer, typed: "ok", candidates: [remembered("ok नहीं", count: 40)],
            generation: query.generation)
        let update = session.resolve(request.candidates, for: request, now: moment, elapsedMilliseconds: 0)
        #expect(update?.suggestion.accepting == nil)
    }

    @Test("A generated line in another script is never drawn, as the leader or among the alternatives.")
    func generatedNonLatinIsDropped() throws {
        var session = SuggestionSession()
        let query = try asked(session.turn(in: composer, at: PredictionContext(typed: "kal ")))
        let silent = session.resolveGenerated(["kal मिलते हैं"], for: query, elapsedMilliseconds: 0)
        #expect(silent == .quiet(because: .nothingOffered))
        _ = session.resolveGenerated(["kal मिलते हैं", "kal milte hain"], for: query, elapsedMilliseconds: 0)
        #expect(session.suggestion == .certain("kal milte hain"))
        let expanded = session.expandGenerated(["kal 见", "kal pakka"], for: query)
        #expect(expanded?.suggestion == .choice(leader: "kal milte hain", others: ["kal pakka"]))
    }
}
