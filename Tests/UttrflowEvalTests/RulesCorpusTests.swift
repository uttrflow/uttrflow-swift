import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// The corpus cases the deterministic passes must pass on their own, with no model anywhere near them.
@Suite("The rules over the corpus")
struct RulesCorpusTests {
    /// Every case the passes are answerable for; one leaving this list is a regression, not a tuning choice.
    static let rulesMustPass: Set<String> = [
        "false-start", "self-correction", "filler-heavy", "noun-spelled-like-a-filler",
        "pronoun-i", "number-words", "short-yes",
        "filler-carrying-a-question-mark", "filler-carrying-an-exclamation-mark",
        "filler-between-commas",
        "repeated-phrase", "i-mean-correction", "actually-between-numbers", "false-no-stays",
        "coordinated-list-kept", "repeated-frame-kept", "emphatic-double-kept",
        "doubled-place-name-kept", "coordinated-apology-kept", "spoken-comma",
        "comma-as-a-word", "quotation-opening-the-text", "new-paragraph", "time-of-day",
        "percentage", "money",
        "period-as-a-word", "spoken-period",
        "period-after-new-line", "dates", "ordinal-not-date",
        "version-number", "port-number", "acronyms", "kubernetes", "function-name", "sql-terms",
        "extension-repeated-digits", "door-code-repeated-digits", "card-group-repeated-digits",
        "dictated-question", "dictated-instruction", "injection", "asks-for-help", "sounds-like-a-prompt",
        "message-two-sentences-no-stop", "mid-sentence-continues-lower-case", "spreadsheet-cell-no-stop",
        "document-sentence-with-stop", "document-list-only-when-spoken", "document-sentence-not-a-list",
        "document-sentence-ending-in-a-percentage", "document-sentence-ending-in-a-close-quote",
        "document-bullet-caret-capitalises", "document-numbered-caret-capitalises",
        "spreadsheet-number-in-cell", "spreadsheet-percentage-in-cell", "sql-editor-prose-stays-prose",
        "sql-editor-numerals", "code-editor-line-break-preserved", "code-editor-numeral-no-stop",
        "message-short-no-stop", "email-greeting-kept", "email-continues-mid-sentence",
        "email-two-paragraphs",
    ]

    /// Destination cases only the model can pass: a spelling off the screen, or a question mark from a sentence's shape.
    static let modelOnly: Set<String> = [
        "sql-editor-identifier-from-screen", "code-editor-identifier-from-screen",
        "message-question-keeps-its-mark", "doubtful-word-from-window",
    ]

    /// The request the bake-off hands an engine, with the case's own destination and caret.
    private func score(_ testCase: EvaluationCase) async throws -> CaseScore {
        let result = try await RuleBasedTransformer().transform(testCase.transformationRequest())
        return Scorer.score(result.text, against: testCase)
    }

    @Test(
        "passes every case the passes are answerable for",
        arguments: EvaluationCorpus.all.filter { rulesMustPass.contains($0.id) })
    func passes(testCase: EvaluationCase) async throws {
        let score = try await score(testCase)
        #expect(
            score.passed,
            "\(testCase.id): \(Int(score.similarity * 100))%, lost \(score.lost), \(score.invented) \(score.brokeShape)"
        )
    }

    @Test("passes every case that names its destination, under that destination's formatter and its caret")
    func passesDestinationCases() {
        // Grammar cases name a destination too, but repairs are the model's alone; the floor is below.
        let named = Set(
            EvaluationCorpus.all.filter { $0.destination != .plain && $0.category != .grammar }.map(\.id))
        #expect(named.count == 24)
        #expect(named.subtracting(Self.modelOnly).isSubset(of: Self.rulesMustPass))
        #expect(Self.modelOnly.isSubset(of: named))
        #expect(Self.modelOnly.isDisjoint(with: Self.rulesMustPass))
        #expect(Set(EvaluationCorpus.cases(in: .grammar).map(\.id)).isDisjoint(with: Self.rulesMustPass))
    }

    /// The floor must never "fix" grammar: a slip goes through the passes untouched but for Tier 1 cleaning.
    @Test(
        "leaves every grammar case's words alone, slips and dialect alike",
        arguments: [
            ("agreement-there-is", "There is three of them waiting outside."),
            ("agreement-he-dont", "He don't know about the meeting yet."),
            ("participle-have-went", "I have went through the whole report twice."),
            ("article-a-apple", "There was a apple left in the bowl."),
            ("tense-drift", "Yesterday I open the file and it crashes immediately."),
            ("tense-drift-over-a-stem", "Yesterday I try to fix the build twice."),
            ("preposition-slip", "She is good in maths and physics."),
            ("plural-slip", "We need two more developer on this team."),
            ("dialect-gonna", "We're gonna ship it friday."),
            ("dialect-aint", "That ain't going to work for the client."),
            ("dialect-me-and-him", "Me and him went through the numbers again."),
            ("double-negative-keep", "We didn't do nothing wrong in that release."),
            ("message-he-dont", "He don't know yet"),
            ("message-there-is", "There is three of them"),
        ])
    func rulesLeaveGrammarAlone(id: String, expected: String) async throws {
        let testCase = try #require(EvaluationCorpus.cases(in: .grammar).first { $0.id == id })
        #expect(try await RuleBasedTransformer().transform(testCase.transformationRequest()).text == expected)
    }

    @Test("covers every grammar case in the leave-alone list, so a new slip cannot skip the floor")
    func grammarCasesAreAllHeld() {
        #expect(EvaluationCorpus.cases(in: .grammar).count == 14)
    }

    @Test("gives every destination at least three cases, so the bake-off can score its block")
    func everyDestinationIsMeasured() {
        for destination in Destination.allCases where destination != .plain {
            let count = EvaluationCorpus.all.count { $0.destination == destination }
            #expect(count >= 3, "\(destination) has \(count) cases")
        }
    }

    /// Similarity alone passes a run with one copy gone, so each case must name the whole run it keeps.
    @Test(
        "fails a repeated-digits case that loses half its run",
        arguments: [
            ("door-code-repeated-digits", "The door code is four seven."),
            ("card-group-repeated-digits", "The test card number starts four two four two."),
            ("extension-repeated-digits", "You can reach me on extension 442."),
        ])
    func halvedRunFails(id: String, halved: String) throws {
        let testCase = try #require(EvaluationCorpus.all.first { $0.id == id })
        #expect(!Scorer.score(halved, against: testCase).passed)
    }

    @Test("names only cases that exist")
    func namesRealCases() {
        let ids = Set(EvaluationCorpus.all.map(\.id))
        #expect(
            Self.rulesMustPass.isSubset(of: ids),
            "\(Self.rulesMustPass.subtracting(ids)) are not in the corpus")
    }

    @Test(
        "writes the exact reference for the cases that have one right answer",
        arguments: [
            ("self-correction", "Let's meet at five on tuesday."),
            ("version-number", "We're on postgres 16.2 right now."),
            ("spoken-comma", "We still need milk, eggs, and bread from the shop."),
            ("new-paragraph", "Thanks for the update.\n\nThe second issue is the login timeout."),
            ("time-of-day", "The dentist moved my appointment to 2:30 pm tomorrow."),
            ("port-number", "The gateway listens on port 8080 in staging."),
            ("percentage", "Conversion dropped by 5% after the redesign."),
            ("money", "The taxi cost 5 dollars."),
            ("actually-between-numbers", "Let's get coffee at three."),
            ("period-as-a-word", "The trial period ended last week."),
            ("spoken-period", "Ship it."),
            ("period-after-new-line", "First line\nsecond line."),
            ("dates", "The 25 March."),
            ("ordinal-not-date", "The twenty first may fail."),
            ("message-two-sentences-no-stop", "Are you around yet I should be there in 10"),
            ("mid-sentence-continues-lower-case", "the deployment script timed out."),
            ("spreadsheet-cell-no-stop", "total revenue for the quarter"),
            ("document-sentence-with-stop", "The quarterly report is attached for your review."),
            (
                "document-list-only-when-spoken",
                "What's left to pack\n- The tent\n- The stove\n- The first aid kit"
            ),
            ("spreadsheet-number-in-cell", "marketing spend for march is 12,000"),
            ("spreadsheet-percentage-in-cell", "churn rate is 4.5%"),
            ("code-editor-line-break-preserved", "Retry the request\nlog the failure"),
            ("code-editor-numeral-no-stop", "Bump the retry count to 20"),
            ("message-short-no-stop", "Leaving now see you at the cafe"),
            ("email-continues-mid-sentence", "the quote you sent last week."),
            (
                "email-two-paragraphs",
                "Thanks for your note.\n\nI've attached the revised quote for the second floor."
            ),
        ])
    func exactText(id: String, expected: String) async throws {
        let testCase = try #require(EvaluationCorpus.all.first { $0.id == id })
        #expect(try await RuleBasedTransformer().transform(testCase.transformationRequest()).text == expected)
    }
}
