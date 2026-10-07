import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowEval

/// The meaning guard's false-refusal rate over the corpus's expected texts. See `Docs/mutation-guard.md`.
@Suite("Meaning guard false refusals over the cleanup corpus")
struct MeaningGuardRefusalRateTests {
    /// Refusals still open, each with the issue that owns it; the gate lets this list fall and never rise.
    static let acknowledged: [String: Int] = [
        "spoken-colon-before-an-item": 5083,
        "spoken-domain-api-path": 5083,
        "numbered-items-repeated-label": 5083,
        "code-editor-spoken-camel-case": 5083,
        "code-editor-spoken-snake-case": 5083,
        "code-editor-spoken-empty-parentheses": 5083,
        "code-editor-spoken-case-stops-at-comma": 5083,
        "code-editor-spoken-equals": 5083,
        "fmt-quote-said": 5083,
        "fmt-bracket-aside": 5083,
        "fmt-paren-aside": 5083,
        "fmt-ellipsis-spoken-dot-dot-dot": 5083,
        "fmt-ellipsis-named": 5083,
        "fmt-list-first-second-third": 5083,
        "fmt-list-bullet-command": 5083,
        "fmt-paragraph-next-line": 5083,
        "tense-drift": 5082,
        "agreement-each-of-have": 5082,
        "tense-drift-last-night": 5082,
        "tense-drift-last-week": 5082,
        "restatement-slot-adjacent": 5084,
        "restatement-slot-apart": 5084,
        "answer-no-before-a-restated-phrase": 5084,
        "hinglish-correction-nahi-nahi": 5084,
        "sql-editor-totals": 5084,
        "slack-name-spelling": 5084,
    ]

    /// Whole-dictation genre references still refused, all owned by #5365; the list only falls.
    static let genreAcknowledged: Set<String> = [
        "genre-customer-email-late-parcel",
        "genre-customer-email-account-question",
        "genre-customer-email-booking-change",
        "genre-chat-reply-weekend-plan",
        "genre-meeting-minutes-planning-sync",
        "genre-invitation-retirement-lunch",
        "genre-invitation-study-group",
        "genre-shopping-list-weekly-shop",
        "genre-shopping-list-hardware-run",
        "genre-recipe-lentil-soup",
        "genre-recipe-flatbreads",
        "genre-recipe-overnight-oats",
        "genre-travel-plan-rail-trip",
        "genre-travel-plan-road-trip",
        "genre-travel-plan-city-weekend",
        "genre-clinic-note-knee-review",
        "genre-clinic-note-blood-pressure",
        "genre-clinic-note-child-fever",
        "genre-legal-clause-termination",
        "genre-poem-harbour-morning",
        "genre-product-description-desk-lamp",
        "genre-product-description-rain-jacket",
        "genre-social-post-marathon",
        "genre-social-post-bakery-opening",
        "genre-social-post-volunteer-call",
        "genre-announcement-pool-maintenance",
        "genre-corrected-reply-meeting-time",
        "genre-corrected-reply-order-quantity",
        "genre-corrected-reply-address-fix",
        "genre-hinglish-technical-sprint-plan",
    ]

    /// Judges each expected text against its own cleaned draft under the case's own formatter, as the engine does.
    static func refusals(
        in corpus: [EvaluationCase] = EvaluationCorpus.all
    ) -> [(id: String, kind: RefusalKind, reason: String)] {
        let guarder = MeaningPreservationGuard()
        return corpus.compactMap { sample in
            let verdict = guarder.verdict(
                onReference: sample.expected, spoken: sample.spoken, in: sample.situation)
            guard case .rejected(let reason, let kind) = verdict else { return nil }
            return (sample.id, kind, reason)
        }
    }

    @Test("every refused expected text is acknowledged with an issue, so the count never rises")
    func noUnacknowledgedRefusal() {
        let refused = Self.refusals()
        print(
            "meaning guard false refusals: \(refused.count) of \(EvaluationCorpus.all.count) expected texts")
        for refusal in refused {
            print("  \(refusal.id)  \(refusal.kind)  \(refusal.reason)")
        }
        let open = refused.filter { Self.acknowledged[$0.id] == nil }.map(\.id)
        #expect(open.isEmpty, "the guard refuses these expected texts: \(open)")
    }

    @Test("an acknowledged refusal that no longer happens is removed, so the count falls")
    func noStaleAcknowledgement() {
        let refused = Set(Self.refusals().map(\.id))
        let stale = Self.acknowledged.keys.filter { !refused.contains($0) }.sorted()
        #expect(stale.isEmpty, "these are accepted now; remove them from the list: \(stale)")
    }

    @Test(
        "genre references: every refusal is acknowledged, and an acknowledgement that no longer refuses is removed"
    )
    func genreRefusalsOnlyFall() {
        let refused = Set(Self.refusals(in: EvaluationCorpus.genres).map(\.id))
        #expect(
            refused.subtracting(Self.genreAcknowledged).isEmpty,
            "newly refused: \(refused.subtracting(Self.genreAcknowledged).sorted())")
        #expect(
            Self.genreAcknowledged.subtracting(refused).isEmpty,
            "accepted now; remove: \(Self.genreAcknowledged.subtracting(refused).sorted())")
    }
}
