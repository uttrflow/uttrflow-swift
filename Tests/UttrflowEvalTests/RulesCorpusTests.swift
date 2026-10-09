import Testing
import UttrflowAI
import UttrflowCore
import UttrflowTestSupport

@testable import UttrflowEval

/// The corpus cases the deterministic passes must pass on their own, with no model anywhere near them.
@Suite("The rules over the corpus")
struct RulesCorpusTests {
    /// What the rules alone write for every corpus case, as last recorded in `Golden/rules.golden`.
    static let golden = GoldenFile(suite: "rules")

    /// Every case whose recorded rules output passes; a case leaving it shows as a golden diff, not a tuning choice.
    static let rulesMustPass: Set<String> = {
        let recorded = (try? golden.recorded()) ?? [:]
        return Set(
            EvaluationCorpus.all.filter { testCase in
                recorded[testCase.id].map { Scorer.score($0, against: testCase).passed } ?? false
            }.map(\.id))
    }()

    /// Destination cases only the model can pass: a spelling off the screen, or a question mark from a sentence's shape.
    static let modelOnly: Set<String> = [
        "sql-editor-identifier-from-screen", "code-editor-identifier-from-screen",
        "doubtful-word-from-window",
    ]

    /// Probe and developer cases the rules still fail, a baseline that only shrinks: a passing case leaves it.
    static let knownFailures: Set<String> = [
        "probe-ticket-and-units", "probe-backtick-identifiers", "probe-repro-steps", "probe-docker-run-flags",
        "probe-sql-join", "probe-regex-pattern", "probe-yaml-keys", "probe-todo-comment", "probe-log-call",
        "probe-version-bump", "probe-dockerfile-from", "probe-git-commands", "probe-stack-frame",
        "probe-protocol-names", "probe-bug-title",
        "probe-docker-build-no-cache", "probe-support-email", "probe-laugh-then-question",
        "probe-meeting-notes",
        "probe-apology-message", "probe-cover-letter", "probe-meeting-time-zones",
        "probe-flight-details", "probe-hashtag-and-handle", "probe-phone-and-address",
        "probe-hinglish-status",
        "probe-quote-unquote", "terminal-spoken-new-line-stays-on-one-line",
        "terminal-spoken-new-paragraph-stays-on-one-line",
        "dev-standup-update", "dev-pr-description-list", "dev-bug-report-steps", "dev-version-bump",
        "dev-design-note-acronyms", "dev-changelog-entry", "dev-decision-record",
        "dev-force-push-correction", "dev-incident-note", "dev-review-reply",
        "dev-onboarding-message", "dev-hotfix-handoff",
    ]

    /// The request the bake-off hands an engine, with the case's own destination and caret.
    private func score(_ testCase: EvaluationCase) async throws -> CaseScore {
        let result = try await RuleBasedTransformer().transform(testCase.transformationRequest())
        return Scorer.score(result.text, against: testCase)
    }

    @Test("writes exactly the recorded output for every corpus case")
    func matchesGolden() async throws {
        var outputs: [String: String] = [:]
        for testCase in EvaluationCorpus.all {
            let result = try await RuleBasedTransformer().transform(testCase.transformationRequest())
            outputs[testCase.id] = result.text
        }
        let inputs = Dictionary(uniqueKeysWithValues: EvaluationCorpus.all.map { ($0.id, $0.spoken) })
        let differences = try Self.golden.compare(outputs, inputs: inputs)
        #expect(
            differences.isEmpty,
            "\(differences.count) outputs moved; rerun with \(GoldenFile.updateVariable)=1 if intended:\n\(differences.map(\.description).joined(separator: "\n"))"
        )
    }

    @Test("writes every launcher query or command lower case as spoken, with no stop")
    func rulesWriteCommandInputAsSpoken() async throws {
        #expect(EvaluationCorpus.cases(in: .commandInput).count == 8)
        for testCase in EvaluationCorpus.cases(in: .commandInput) {
            let result = try await RuleBasedTransformer().transform(testCase.transformationRequest())
            #expect(result.text == testCase.expectedExact, "\(testCase.id)")
        }
    }

    @Test("never writes a line break into a terminal, where one is Return")
    func terminalCasesStayOnOneLine() async throws {
        let terminal = EvaluationCorpus.all.filter { $0.destination == .terminal }
        #expect(terminal.contains { $0.spoken.contains("new line") })
        #expect(terminal.contains { $0.spoken.contains("new paragraph") })
        for testCase in terminal {
            let result = try await RuleBasedTransformer().transform(testCase.transformationRequest())
            #expect(!result.text.contains("\n"), "\(testCase.id)")
        }
    }

    @Test("hands a case's dictionary to the rules, which write a word the entry spells in its spelling")
    func dictionaryReachesTheRules() async throws {
        let testCase = try #require(EvaluationCorpus.all.first { $0.id == "dictionary-entry-case-2302" })
        let withEntries = try await RuleBasedTransformer().transform(testCase.transformationRequest()).text
        let without = EvaluationCase(
            id: testCase.id, category: testCase.category, spoken: testCase.spoken, expected: testCase.expected
        )
        let withoutEntries = try await RuleBasedTransformer().transform(without.transformationRequest()).text
        #expect(withEntries == testCase.expectedExact)
        #expect(withoutEntries.contains("docker"))
    }

    @Test("ends a sentence for every forty words of a long dictation paused between its sentences")
    func longPausedDictationKeepsItsSentences() async throws {
        let testCase = try #require(EvaluationCorpus.all.first { $0.id == "long-input-paused-2351" })
        let words = testCase.spoken.split(whereSeparator: \.isWhitespace).count
        #expect(words >= 300)
        let text = try await RuleBasedTransformer().transform(testCase.transformationRequest()).text
        let ends = Scorer.tokens(text, keepingSentenceEnds: true).count { $0 == Scorer.sentenceEnd } + 1
        #expect(ends * 40 >= words, "\(ends) sentence ends in \(words) words: \(text)")
        #expect(Scorer.score(text, against: testCase).passed)
    }

    @Test("still requires the rules to pass the cases they always have")
    func mustPassIsPopulated() {
        #expect(Self.rulesMustPass.count >= 200)
    }

    @Test("passes every case that names its destination, under that destination's formatter and its caret")
    func passesDestinationCases() {
        // Grammar cases name a destination too, but repairs are the model's alone; the floor is below.
        let named = Set(
            EvaluationCorpus.all.filter { $0.destination != .plain && $0.category != .grammar }.map(\.id))
        #expect(named.count == 188 + Self.knownFailures.count)
        #expect(
            named.subtracting(Self.modelOnly).subtracting(Self.knownFailures).isSubset(of: Self.rulesMustPass)
        )
        #expect(Self.knownFailures.isSubset(of: named))
        #expect(Self.knownFailures.isDisjoint(with: Self.rulesMustPass))
        #expect(Self.modelOnly.isSubset(of: named))
        #expect(Self.modelOnly.isDisjoint(with: Self.rulesMustPass))
        // A grammar case the rules pass is one whose reference keeps the words as spoken, as dialect does.
        let repairs = EvaluationCorpus.cases(in: .grammar).filter { testCase in
            !Self.leftAlone.contains { $0.id == testCase.id && $0.text == testCase.expected }
        }
        #expect(Set(repairs.map(\.id)).isDisjoint(with: Self.rulesMustPass))
    }

    /// What the rules write for every grammar case: the floor never "fixes" grammar, so only Tier 1 cleaning touches it.
    static let leftAlone: [(id: String, text: String)] = [
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
        ("agreement-here-is-two", "Here is two options for the launch."),
        ("agreement-each-of-have", "Each of the boxes have a label on the lid."),
        ("article-an-before-consonant-sound", "We ordered an unicorn cake for the party."),
        ("article-a-before-silent-h", "She is a honest reviewer."),
        ("preposition-discussed-about", "We discussed about the budget on Monday."),
        ("preposition-depends-of", "The date depends of the weather."),
        ("tense-drift-last-night", "Last night I finish the draft and send it to the editor."),
        ("tense-drift-last-week", "Last week the printer jams twice and nobody fixes it."),
        ("dialect-gonna", "We're gonna ship it Friday."),
        ("dialect-aint", "That ain't going to work for the client."),
        ("dialect-me-and-him", "Me and him went through the numbers again."),
        ("double-negative-keep", "We didn't do nothing wrong in that release."),
        ("message-he-dont", "He don't know yet"),
        ("message-there-is", "There is three of them"),
        ("message-dialect-he-come", "He come by yesterday"),
        ("message-dialect-i-seen", "I seen it yesterday"),
        ("message-dialect-they-was", "They was at the shop"),
        ("message-dialect-we-was", "We was just talking about you"),
    ]

    @Test("leaves every grammar case's words alone, slips and dialect alike", arguments: leftAlone)
    func rulesLeaveGrammarAlone(id: String, expected: String) async throws {
        let testCase = try #require(EvaluationCorpus.cases(in: .grammar).first { $0.id == id })
        #expect(try await RuleBasedTransformer().transform(testCase.transformationRequest()).text == expected)
    }

    @Test("covers every grammar case in the leave-alone list, so a new slip cannot skip the floor")
    func grammarCasesAreAllHeld() {
        #expect(EvaluationCorpus.cases(in: .grammar).count == 34)
    }

    @Test("writes every second-language case as spoken, with no article, preposition or tense repaired")
    func rulesKeepSecondLanguageGrammar() async throws {
        #expect(EvaluationCorpus.secondLanguage.count == 40)
        for testCase in EvaluationCorpus.secondLanguage {
            let written = try await RuleBasedTransformer().transform(testCase.transformationRequest()).text
            #expect(written == testCase.expected, "\(testCase.id) wrote \(written)")
        }
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
            ("self-correction", "Let's meet at five on Tuesday."),
            ("ellipsis-glued-fillers", "The...the invoice is...overdue."),
            ("version-number", "We're on postgres 16.2 right now."),
            ("spoken-decade", "The 1990s were fun."),
            ("twenty-four-seven-idiom", "It's a twenty four seven service."),
            ("fifty-fifty-idiom", "It's fifty fifty."),
            ("page-fraction", "Page 2 of 3."),
            ("spoken-comma", "We still need milk, eggs, and bread from the shop."),
            ("spoken-comma-before-next-sentence-of-course", "We shipped, of course it broke."),
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
            ("code-editor-comment-gets-a-stop", "The comment explains why the cache clears."),
            ("code-editor-comment-keeps-its-stop", "The retry count resets after a failure."),
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

    @Test("a spoken comma before a new sentence is written without keeping the mark word")
    func spokenCommaBeforeNextSentenceOfCourse() async throws {
        let testCase = try #require(
            EvaluationCorpus.all.first { $0.id == "spoken-comma-before-next-sentence-of-course" })
        let result = try await RuleBasedTransformer().transform(testCase.transformationRequest())

        #expect(result.text == testCase.expected)
    }
}
