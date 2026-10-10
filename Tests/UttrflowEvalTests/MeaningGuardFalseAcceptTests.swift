import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowEval

/// The meaning guard's false-accept rate per class of model error. See `Docs/mutation-guard.md`.
@Suite("Meaning guard false accepts over a classed model-error set")
struct MeaningGuardFalseAcceptTests {
    /// Accepted mutations per class at the last measurement; the gate lets each fall and never rise.
    static let baseline: [ModelErrorClass: Int] = [
        .dropContentWord: 10, .swapWords: 2, .appendClause: 2, .wrapInLabel: 1,
    ]

    struct Judged {
        let id: String
        let errorClass: ModelErrorClass
        let rewrite: String
        let accepted: Bool
    }

    /// The cases judged, by id, so a case added to the corpus never changes which mutations the baseline counts.
    static let caseIDs: [String] = [
        "np3", "lowercase-start-after-complete-sentence-ebay",
        "lowercase-start-after-complete-sentence-pronoun", "lowercase-start-after-complete-sentence-that",
        "demonstrative-opening-that-was-good-point", "deictic-opening-here-is-list",
        "deictic-opening-here-are-files", "indian-grouping-quote", "indian-grouping-total-bill",
        "filler-heavy", "filler-between-commas", "coordination-kept-not-restatement",
        "repeated-frame-for-kept", "no-punctuation", "paused-two-statements", "paused-after-article-runs-on",
        "page-fraction", "strike-that-as-an-order-kept", "or-rather-before-a-negation-kept",
        "actually-make-that-as-making-kept", "false-no-stays", "doubled-place-name-kept", "comma-as-a-word",
        "spoken-commas-around-a-clause", "spoken-percent-sign-after-a-number", "comma-separated-as-words",
        "period-furniture-as-words", "right-homophones-kept", "full-stop-new-paragraph", "time-of-day",
        "money", "ordinal-not-date", "run-on-small-words-alarm", "run-on-small-words-heating",
        "run-on-small-words-offer", "run-on-small-words-dinner", "run-on-small-words-parcel",
        "run-on-small-words-volume", "run-on-small-words-shift", "paused-full-stop-6688",
        "zone-letters-after-am-4031", "zone-utc-offset-half-hour-4031", "zone-utc-word-offset-4031",
        "zone-coordinated-universal-4031", "zone-pacific-time-zone-4031",
        "initialisms-spelled-as-letter-names", "joined-r-and-d", "number-before-written-unit-symbol",
        "door-code-repeated-digits", "spoken-code-digit-run", "spoken-emergency-digit-run",
        "look-at-a-domain-as-words", "prose-double-dash-option-name", "spelled-short-commit-hash",
        "spelled-unit-symbol-kg", "spelled-unit-symbol-km", "spelled-unit-symbol-hz",
        "spelled-unit-symbol-tb", "spelled-unit-symbol-mb", "spelled-unit-symbol-mph",
        "spelled-unit-symbol-kcal", "spelled-unit-symbol-bpm", "spelled-unit-letters-without-number",
        "negated-option-verify-prose", "sql-statement-greater-than", "sql-statement-less-than",
        "sql-statement-less-or-equal", "sql-statement-between", "sql-statement-order-asc-limit",
        "sql-statement-left-join", "sql-statement-between-ratings", "sql-statement-null-and",
        "request-question-personal-weekend", "request-question-rhetorical-printer",
        "request-question-speed-of-light", "request-format-number-only", "request-format-lowercase",
        "request-polite-could-you-check", "request-hindi-translate-devanagari", "request-refusal-lock",
        "request-refusal-password", "request-refusal-medical", "hostile-title-injection",
        "hostile-title-code", "hostile-app-preamble", "hostile-app-code", "hostile-caret-preamble",
        "hostile-reading-forced-reply", "hostile-reading-code", "hostile-line-typed-into-editor",
        "hostile-line-typed-into-terminal", "hinglish-galat-bola-restatement-kept",
        "hinglish-correction-replaced-head", "editor-identifier-casing", "editor-selected-identifier",
        "editor-ordinary-question", "calendar-title-keeps-question-mark", "quick-entry-calendar-time",
        "document-bullet-caret-capitalises", "document-number-one-after-a-sentence-not-an-item",
        "numbered-items-three-of-them", "numbered-items-a-plan", "numbered-items-priorities",
        "numbered-items-reminders", "number-invoice-not-an-item", "number-gate-not-an-item",
        "spreadsheet-number-in-cell", "spreadsheet-percentage-in-cell", "code-editor-identifier-from-screen",
        "code-editor-numeral-no-stop", "email-greeting-kept", "email-continues-mid-sentence",
        "doubtful-word-heard-word-stands", "dictation-keeps-markdown-words-heading-digit-two",
        "dictation-keeps-markdown-words-heading-three", "dictation-keeps-markdown-words-bold",
        "sql-editor-two-sentences", "document-spoken-colon-before-a-numbered-list",
        "notes-prose-at-after-email-stays", "document-spoken-email-after-is", "document-one-line-lease-title",
        "document-one-line-save-name", "spreadsheet-search-room-number", "sql-editor-one-line-favorite",
        "sql-editor-search-pgadmin", "code-editor-one-line-nova", "code-editor-one-line-pycharm",
        "messaging-one-line-discord", "messaging-search-lunch", "email-search-shipping",
        "email-subject-travel", "code-token-caret-i-95", "code-token-word-caret-quarter",
        "code-token-word-seam-after", "participle-had-took", "participle-has-drove", "agreement-each-of-have",
        "tense-drift-last-night", "tense-drift-last-week", "message-dialect-we-was",
        "second-language-article-added-nature", "second-language-article-added-advice",
        "second-language-preposition-married-with", "second-language-preposition-reach-at",
        "second-language-tense-did-went", "second-language-tense-since-morning", "one-line-room",
        "one-line-reason", "one-line-two-sentences", "literal-prose-ten-percent",
        "literal-prose-version-sentence", "literal-prose-path-sentence", "fmt-boundary-single-word",
        "fmt-question-after-statement", "fmt-quote-open-close", "fmt-quote-nested", "fmt-paren-aside",
        "fmt-token-mixed-case-brand", "fmt-number-percent", "fmt-number-money",
        "fmt-number-repeated-port-followed-by-quantity", "fmt-list-first-second-third",
        "fmt-paragraph-new-paragraph", "fmt-destination-email-sentence", "fmt-hinglish-question",
        "probe-ticket-and-units", "probe-retry-bullets", "probe-repro-steps", "probe-stack-frame",
        "probe-protocol-names", "probe-changelog-bullets", "probe-decision-record", "probe-revenue-figures",
        "probe-option-pricing", "probe-apology-message", "probe-meeting-time-zones",
        "probe-recipe-quantities", "probe-flight-details", "probe-clinical-note", "probe-contract-clauses",
        "probe-quoted-citation", "probe-short-verse", "probe-topic-shifts", "caret-before-comma",
        "caret-before-paragraph-asks", "caret-before-parenthetical-joined", "caret-before-open-quote",
        "caret-replace-whole-sentence", "fmt-casing-mention-was", "fmt-casing-span-without-off",
        "mix-en-noun-start-paisa", "mix-en-noun-middle-chabi", "mix-en-noun-end-baarish",
        "mix-en-verb-middle-bhej-do", "mix-en-verb-end-nikal-jao", "mix-en-number-start-paanch",
        "mix-en-name-start-nani", "mix-en-name-middle-mama", "mix-en-name-end-chachi",
        "mix-en-name-end-bhaiya-end", "mix-en-particle-start-bas", "mix-en-question-tag-middle-theek-hai-mid",
        "mix-hi-noun-start-office", "mix-hi-noun-middle-rent", "mix-hi-noun-end-charger",
        "mix-hi-noun-end-deadline", "mix-hi-number-end-seven-end", "mix-hi-number-end-two-end",
        "mix-hi-name-start-dad", "mix-hi-particle-end-anyway-end", "mix-hi-question-tag-middle-okay-mid",
        "mix-hi-question-tag-end-okay-end", "segment-student-abbreviation-ie",
        "segment-support-agent-product-name", "segment-support-agent-short-close",
        "segment-researcher-author-year", "segment-researcher-sample-size", "long-input-meeting-notes-2350",
        "long-input-paused-2351", "dev-standup-update", "dev-review-comment", "dev-commit-message",
        "dev-bug-report-steps", "dev-readme-commands", "dev-endpoint-summary", "dev-version-bump",
        "dev-design-note-acronyms", "dev-env-setup", "dev-letter-run-beside-number", "dev-incident-note",
        "dev-test-failure-report", "dev-hotfix-handoff", "dev-feature-flag-rollout",
        "dictionary-entry-case-2302", "dictionary-symbol-only-entry-2343",
        "dictionary-lower-case-start-document-4290", "dictionary-lower-case-after-stop-code-4290",
        "web-search-field-2280", "source-swift-divide-equals", "source-swift-less-than",
        "source-swift-not-equals-nil", "source-swift-greater-than-zero", "source-python-double-equals",
        "source-python-power-assign", "source-python-greater-than-zero",
        "source-python-triple-equals-not-python", "source-javascript-divide-equals",
    ]

    /// The named cases, in the order named; a renamed or removed id fails `namedCasesExist`.
    static var namedCases: [EvaluationCase] {
        let byID = Dictionary(
            EvaluationCorpus.all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return caseIDs.compactMap { byID[$0] }
    }

    /// Judges every mutation of each named case the guard accepts, as the engine judges a rewrite.
    static func judged() async -> [Judged] {
        let guarder = MeaningPreservationGuard()
        var correct: [String: Bool] = [:]
        var judged: [Judged] = []
        for (sample, errorClass, rewrite) in ModelErrorClass.mutations(of: namedCases) {
            let request = sample.transformationRequest()
            if correct[sample.id] == nil {
                correct[sample.id] = await guarder.verdict(onReference: sample.expected, for: request)
                    .isAccepted
            }
            guard correct[sample.id] == true else { continue }
            let verdict = await guarder.verdict(onReference: rewrite, for: request)
            judged.append(
                Judged(id: sample.id, errorClass: errorClass, rewrite: rewrite, accepted: verdict.isAccepted))
        }
        return judged
    }

    @Test("over a hundred cases, each class lets through exactly its baseline, so a fix lowers it")
    func falseAcceptsOnlyFall() async {
        let all = await Self.judged()
        print("meaning guard false accepts over \(all.count) mutations of \(Set(all.map(\.id)).count) cases")
        #expect(Set(all.map(\.id)).count >= 100)
        for errorClass in ModelErrorClass.allCases {
            let ofClass = all.filter { $0.errorClass == errorClass }
            let accepted = ofClass.filter(\.accepted)
            print("  \(errorClass)  \(accepted.count) of \(ofClass.count)")
            for mutation in accepted { print("    \(mutation.id)  \(mutation.rewrite)") }
            #expect(ofClass.count >= 20, "\(errorClass) has too few mutations")
            #expect(
                accepted.count == Self.baseline[errorClass, default: 0],
                "\(errorClass) accepts \(accepted.count); the baseline says \(Self.baseline[errorClass, default: 0])"
            )
        }
    }

    @Test("every named case is still in the corpus, so the judged set cannot shrink unseen")
    func namedCasesExist() {
        let ids = Set(EvaluationCorpus.all.map(\.id))
        #expect(Self.caseIDs.filter { !ids.contains($0) } == [])
        #expect(Set(Self.caseIDs).count == Self.caseIDs.count)
    }

    @Test(
        "each class makes the error it names",
        arguments: [
            (ModelErrorClass.dropContentWord, "Send the report today.", "The report today."),
            (.addNegation, "The build is ready.", "The build is not ready."),
            (.swapWords, "We send report today.", "We report send today."),
            (.changeNumber, "Meet at 5 pm.", "Meet at 6 pm."),
            (.appendClause, "Ship it.", "Ship it. Also remember to book the meeting room."),
            (
                .answerInsteadOfTidy, "Ship it.",
                "Sure, I can help with that. What would you like me to change?"
            ),
            (.translate, "Send the file and the notes.", "Send el file y el notes."),
            (.wrapInLabel, "Ship it.", "Here is the cleaned text: Ship it."),
            (
                .moveWordAcrossSentence, "Please send the report. Then call me.",
                "Please the report. Then call me send."
            ),
        ]
    )
    func mutates(errorClass: ModelErrorClass, text: String, expected: String) {
        #expect(errorClass.mutate(text, seed: 0) == expected)
    }

    @Test(
        "a class with nothing to act on makes no mutation",
        arguments: [
            (ModelErrorClass.dropContentWord, "Ship it."), (.addNegation, "Ship it."),
            (.swapWords, "Ship it."),
            (.changeNumber, "Ship it."), (.translate, "Ship it."), (.moveWordAcrossSentence, "Ship it."),
        ]
    )
    func leavesTextWithoutATarget(errorClass: ModelErrorClass, text: String) {
        #expect(errorClass.mutate(text, seed: 0) == nil)
    }

    @Test("a per-class limit keeps that many of each class, spread over the corpus")
    func samplesEvenly() {
        let all = ModelErrorClass.mutations(of: EvaluationCorpus.all)
        let sampled = ModelErrorClass.mutations(of: EvaluationCorpus.all, perClass: 20)
        for errorClass in ModelErrorClass.allCases {
            let ofClass = sampled.filter { $0.errorClass == errorClass }
            #expect(ofClass.count == min(20, all.count { $0.errorClass == errorClass }))
        }
        #expect(Set(sampled.map(\.sample.id)).count > 100)
    }
}
