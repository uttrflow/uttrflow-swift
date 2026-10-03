import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// The corpus cases the deterministic passes must pass on their own, with no model anywhere near them.
@Suite("The rules over the corpus")
struct RulesCorpusTests {
    /// Every case the passes are answerable for; one leaving this list is a regression, not a tuning choice.
    static let rulesMustPass: Set<String> = [
        "np3", "sub1", "sub4", "bec1", "and1", "but1",
        "pronoun-opening-that-is-it", "pronoun-opening-it-is-good-idea",
        "demonstrative-opening-this-is-good-idea", "demonstrative-opening-that-was-good-point",
        "pronoun-opening-it-is-my-two-cents", "pronoun-opening-i-am-sure",
        "pronoun-opening-it-is-good-control", "pronoun-opening-she-is-nurse-control",
        "determiner-opening-report-is-idea-control", "pronoun-opening-it-is-not-idea-control",
        "deictic-opening-here-is-list", "deictic-opening-here-are-files", "deictic-opening-there-is-list",
        "pronoun-opening-everything-is", "pronoun-opening-nothing-is",
        "false-start", "self-correction", "single-word-self-correction",
        "lowercase-start-after-complete-sentence-ebay",
        "lowercase-start-after-complete-sentence-pronoun",
        "lowercase-start-after-complete-sentence-vitals",
        "lowercase-start-after-complete-sentence-that",
        "lowercase-start-after-complete-sentence-she", "lowercase-start-after-answer-stops",
        "actually-ordinary-adverb-weather", "actually-ordinary-adverb-sales",
        "actually-ordinary-adverb-server", "actually-ordinary-adverb-team",
        "no-ordinary-determiner-reason", "no-ordinary-determiner-thanks", "filler-heavy",
        "ellipsis-glued-fillers",
        "noun-spelled-like-a-filler",
        "pronoun-i", "initialisms-spelled-as-letter-names", "article-before-spelled-letter",
        "spelled-eg", "spelled-asap", "spelled-apr", "standalone-pronoun-i",
        "number-words", "spoken-decade", "twenty-four-seven-idiom",
        "fifty-fifty-idiom", "page-fraction", "money-billion", "short-yes",
        "filler-carrying-a-question-mark", "filler-carrying-an-exclamation-mark",
        "filler-between-commas",
        "repeated-phrase", "repeated-intensifier-chain", "repeated-continuation-kept",
        "i-mean-correction", "correction-between-commas", "actually-between-numbers",
        "number-correction-with-unit",
        "correction-between-amounts", "correction-between-percentages",
        "false-no-stays",
        "trigger-as-its-own-sentence",
        "coordinated-list-kept", "repeated-frame-kept", "emphatic-double-kept",
        "coordination-kept-not-restatement", "repeated-frame-for-kept",
        "doubled-place-name-kept", "coordinated-apology-kept", "spoken-comma",
        "comma-as-a-word", "quotation-opening-the-text",
        "spoken-comma-after-a-greeting", "spoken-comma-after-an-opener", "spoken-comma-after-yes",
        "spoken-commas-in-a-bare-list", "spoken-comma-before-and", "spoken-colon-before-a-clause",
        "spoken-colon-before-an-item", "spoken-colon-at-the-end", "spoken-dash-before-a-clause",
        "hinglish-spoken-comma-before-aur", "hinglish-spoken-colon-before-kal",
        "colon-cancer-as-words", "colon-trouble-as-words", "colon-surgery-as-words", "colon-health-as-words",
        "comma-separated-as-words", "comma-usage-as-words", "comma-splices-as-words",
        "comma-placement-as-words", "dash-training-as-words", "dash-cam-as-words", "dash-drills-as-words",
        "period-furniture-as-words", "new-paragraph", "time-of-day",
        "percentage", "money",
        "period-as-a-word", "spoken-period", "demonstrative-subject-spoken-period",
        "period-after-new-line", "full-stop-new-paragraph", "question-mark-new-line",
        "dates", "spoken-date-with-the", "spoken-date-without-the",
        "ordinal-not-date", "compound-ordinal-above-one-hundred",
        "version-number", "port-number", "acronyms", "kubernetes", "function-name", "sql-terms",
        "mid-sentence-brand-name-case", "mid-sentence-mixed-case-brand",
        "spoken-email-address", "spoken-email-address-with-a-name",
        "spoken-email-address-ending-the-sentence", "spoken-email-addresses-in-a-list",
        "look-at-a-domain-as-words", "met-at-the-office-as-words",
        "extension-repeated-digits", "door-code-repeated-digits", "card-group-repeated-digits",
        "spoken-phone-digit-run", "spoken-code-digit-run", "spoken-emergency-digit-run",
        "spoken-international-phone-digit-run", "spoken-oh-and-zero-digit-run", "spoken-leading-oh-digit-run",
        "extension-is-digits-kept", "extension-is-spoken-digit-run",
        "two-single-digits-kept", "hyphenated-bedroom-count-kept",
        "dictated-question", "dictated-instruction", "injection", "asks-for-help", "sounds-like-a-prompt",
        "message-two-sentences-no-stop", "mid-sentence-continues-lower-case", "spreadsheet-cell-no-stop",
        "document-sentence-with-stop", "document-list-only-when-spoken", "document-sentence-not-a-list",
        "document-numbered-items-after-a-sentence", "document-number-one-after-a-sentence-not-an-item",
        "document-sentence-ending-in-a-percentage", "document-sentence-ending-in-a-close-quote",
        "document-bullet-caret-capitalises", "document-numbered-caret-capitalises",
        "spreadsheet-number-in-cell", "spreadsheet-percentage-in-cell", "sql-editor-prose-stays-prose",
        "sql-editor-numerals", "sql-editor-large-number-ungrouped",
        "code-editor-large-number-ungrouped",
        "code-editor-line-break-preserved", "code-editor-numeral-no-stop",
        "code-editor-code-keeps-no-stop", "code-editor-comment-gets-a-stop",
        "code-editor-comment-keeps-its-stop",
        "terminal-command-keeps-case", "terminal-command-keeps-case-mid-pipeline",
        "terminal-command-keeps-no-stop",
        "message-short-no-stop", "email-greeting-kept", "email-continues-mid-sentence",
        "email-two-paragraphs",
        "numbered-items-for-a-trip", "numbered-items-three-of-them", "numbered-items-a-plan",
        "numbered-items-before-lunch", "numbered-items-as-digits", "numbered-items-an-agenda",
        "numbered-items-priorities", "numbered-items-steps", "numbered-items-continuing",
        "numbered-items-reminders", "numbered-items-repeated-label", "number-ring-not-an-item",
        "number-call-not-an-item",
        "number-check-not-an-item", "number-bus-not-an-item", "number-row-not-an-item",
        "number-invoice-not-an-item", "number-gate-not-an-item", "number-platform-not-an-item",
        "number-flight-not-an-item", "number-room-not-an-item", "number-press-not-an-item",
        "number-jersey-not-an-item",
        "hindi-translation-refused", "hindi-worked-example-refused",
        "hinglish-late", "hinglish-trailing-english", "hinglish-false-start",
        "hinglish-correction-nahi-nahi", "hinglish-request",
        "hinglish-question", "hinglish-question-after-verb", "hinglish-kaunsa-question",
        "hinglish-kya-hua-question",
        "hinglish-question-word-after-subject", "hinglish-na-question-tag", "hinglish-apology-kept",
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
        #expect(named.count == 56)
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
            ("participle-have-wrote", "I have wrote the summary already."),
            ("participle-had-took", "I had took the wrong turn."),
            ("participle-should-have-ate", "I should have ate before the call."),
            ("participle-was-wrote", "It was wrote in the notes."),
            ("participle-has-began", "The project has began already."),
            ("participle-have-spoke", "I have spoke with them."),
            ("participle-was-broke", "The window was broke during transit."),
            ("participle-has-drove", "She has drove this route before."),
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
        #expect(EvaluationCorpus.cases(in: .grammar).count == 22)
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

    @Test("fails when the prose repetition is rewritten as the selected identifier")
    func identifierThenProseKeepsProseMention() throws {
        let testCase = try #require(
            EvaluationCorpus.all.first { $0.id == "editor-identifier-then-prose" })
        let score = Scorer.score(
            "We call setUserPrefs at launch, so the settings page never has to setUserPrefs again.",
            against: testCase
        )
        #expect(!score.keptEverythingRequired)
        #expect(score.lost == ["set user prefs"])
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
            ("ellipsis-glued-fillers", "The invoice is overdue."),
            ("version-number", "We're on postgres 16.2 right now."),
            ("spoken-decade", "The 1990s were fun."),
            ("twenty-four-seven-idiom", "It's a twenty four seven service."),
            ("fifty-fifty-idiom", "It's fifty fifty."),
            ("page-fraction", "Page 2 of 3."),
            ("spoken-comma", "We still need milk, eggs, and bread from the shop."),
            ("new-paragraph", "Thanks for the update.\n\nThe second issue is the login timeout."),
            ("time-of-day", "The dentist moved my appointment to 2:30 pm tomorrow."),
            ("port-number", "The gateway listens on port 8080 in staging."),
            ("spoken-phone-digit-run", "Call me on 9876543210."),
            ("spoken-code-digit-run", "The code is 1234."),
            ("spoken-emergency-digit-run", "Call 911."),
            ("spoken-international-phone-digit-run", "Dial +919876543210."),
            ("spoken-oh-and-zero-digit-run", "The passcode is 005."),
            ("spoken-leading-oh-digit-run", "The passcode is 050."),
            ("extension-is-digits-kept", "My extension is 445."),
            ("extension-is-spoken-digit-run", "My extension is 445."),
            ("two-single-digits-kept", "One or two."),
            ("hyphenated-bedroom-count-kept", "Two three-bedroom flats."),
            ("percentage", "Conversion dropped by 5% after the redesign."),
            ("money", "The taxi cost 5 dollars."),
            ("actually-between-numbers", "Let's get coffee at three."),
            ("number-correction-with-unit", "We need 15 boxes."),
            ("period-as-a-word", "The trial period ended last week."),
            ("spoken-period", "Ship it."),
            ("initialisms-spelled-as-letter-names", "The API is down."),
            ("article-before-spelled-letter", "We need a p."),
            ("spelled-eg", "Bring snacks e.g. chips."),
            ("spelled-asap", "We need it ASAP."),
            ("spelled-apr", "Open APR for it."),
            ("standalone-pronoun-i", "So I think."),
            ("period-after-new-line", "First line\nSecond line."),
            ("full-stop-new-paragraph", "The build is green.\n\nThanks everyone."),
            ("dates", "The 25th of March."),
            ("spoken-date-with-the", "The 21st of March."),
            ("spoken-date-without-the", "21st of March."),
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
            ("code-editor-line-break-preserved", "Retry the request\nLog the failure"),
            ("code-editor-numeral-no-stop", "Bump the retry count to 20"),
            ("code-editor-code-keeps-no-stop", "this invalidates the cache after every write"),
            ("code-editor-comment-gets-a-stop", "the comment explains why the cache clears."),
            ("code-editor-comment-keeps-its-stop", "the retry count resets after a failure."),
            ("message-short-no-stop", "Leaving now see you at the cafe"),
            ("email-continues-mid-sentence", "the quote you sent last week."),
            ("spoken-email-address", "Forward the logs to support@example.com."),
            (
                "spoken-email-address-with-a-name",
                "Please send the contract to priya.shah@example.com by tonight."
            ),
            ("spoken-email-address-ending-the-sentence", "Email me at sam@example.com."),
            (
                "spoken-email-addresses-in-a-list",
                "Write to info@example.com and billing@example.net."
            ),
            ("look-at-a-domain-as-words", "Look at example.com when you have a minute."),
            ("met-at-the-office-as-words", "We met at the office at five."),
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
