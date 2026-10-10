import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowEval

/// The meaning guard's false-refusal rate over the corpus's expected texts. See `Docs/mutation-guard.md`.
@Suite("Meaning guard false refusals over the cleanup corpus")
struct MeaningGuardRefusalRateTests {
    /// Refusals still open, each with the issue that owns it; the gate lets this list fall and never rise.
    static let acknowledged: [String: Int] = [
        "fmt-ellipsis-named": 2057,
        "fmt-paragraph-next-line": 5083,
        "agreement-each-of-have": 5082,
        "restatement-slot-adjacent": 5084,
        "restatement-slot-apart": 5084,
        "hinglish-correction-nahi-nahi": 5084,
        "sql-editor-totals": 5084,
        "probe-repro-steps": 6831,
        "probe-protocol-names": 6831,
        "probe-sql-join": 6831,
        "probe-meeting-time-zones": 6873,
        "probe-clinical-note": 6872,
        "probe-backtick-identifiers": 6831,
        "probe-log-call": 6831,
        "probe-regex-pattern": 6403,
        "probe-yaml-keys": 6403,
        "dev-pr-description-list": 6403,
        "dev-env-setup": 6403,
        "spoken-comma-before-next-sentence-of-course": 6402,
        "probe-chained-corrections": 5084,
        "probe-topic-shifts": 5084,
    ]

    /// Whole-dictation genre references still refused, all owned by #5365; the list only falls.
    static let genreAcknowledged: Set<String> = [
        "genre-customer-email-account-question",
        "genre-shopping-list-weekly-shop",
        "genre-shopping-list-hardware-run",
        "genre-recipe-lentil-soup",
        "genre-recipe-flatbreads",
        "genre-recipe-overnight-oats",
        "genre-travel-plan-city-weekend",
        "genre-clinic-note-knee-review",
        "genre-clinic-note-blood-pressure",
        "genre-product-description-desk-lamp",
        "genre-product-description-rain-jacket",
        "genre-social-post-bakery-opening",
        "genre-social-post-volunteer-call",
        "genre-corrected-reply-meeting-time",
        "genre-hinglish-technical-sprint-plan",
    ]

    /// Judges each expected text against the draft and readings the engine would hand the model for the case.
    static func refusals(
        in corpus: [EvaluationCase] = EvaluationCorpus.all
    ) async -> [(id: String, kind: RefusalKind, reason: String)] {
        let guarder = MeaningPreservationGuard()
        var refused: [(id: String, kind: RefusalKind, reason: String)] = []
        for sample in corpus {
            let verdict = await guarder.verdict(
                onReference: sample.expected, for: sample.transformationRequest())
            if case .rejected(let reason, let kind) = verdict { refused.append((sample.id, kind, reason)) }
        }
        return refused
    }

    @Test("judges a doubtful run against the readings the engine offers for it, and no other spelling")
    func judgesAgainstOfferedReadings() async throws {
        let sample = try #require(EvaluationCorpus.all.first { $0.id == "slack-name-spelling" })
        let guarder = MeaningPreservationGuard()
        let request = sample.transformationRequest()
        #expect(await guarder.verdict(onReference: sample.expected, for: request).isAccepted)
        let unoffered = sample.expected.replacingOccurrences(of: "Marcie", with: "Marcia")
        #expect(await !guarder.verdict(onReference: unoffered, for: request).isAccepted)
    }

    @Test("every refused expected text is acknowledged with an issue, so the count never rises")
    func noUnacknowledgedRefusal() async {
        let refused = await Self.refusals()
        print(
            "meaning guard false refusals: \(refused.count) of \(EvaluationCorpus.all.count) expected texts")
        for refusal in refused {
            print("  \(refusal.id)  \(refusal.kind)  \(refusal.reason)")
        }
        let open = refused.filter { Self.acknowledged[$0.id] == nil }.map(\.id)
        #expect(open.isEmpty, "the guard refuses these expected texts: \(open)")
    }

    @Test("an acknowledged refusal that no longer happens is removed, so the count falls")
    func noStaleAcknowledgement() async {
        let refused = Set(await Self.refusals().map(\.id))
        let stale = Self.acknowledged.keys.filter { !refused.contains($0) }.sorted()
        #expect(stale.isEmpty, "these are accepted now; remove them from the list: \(stale)")
    }

    @Test(
        "genre references: every refusal is acknowledged, and an acknowledgement that no longer refuses is removed"
    )
    func genreRefusalsOnlyFall() async {
        let refused = Set(await Self.refusals(in: EvaluationCorpus.genres).map(\.id))
        #expect(
            refused.subtracting(Self.genreAcknowledged).isEmpty,
            "newly refused: \(refused.subtracting(Self.genreAcknowledged).sorted())")
        #expect(
            Self.genreAcknowledged.subtracting(refused).isEmpty,
            "accepted now; remove: \(Self.genreAcknowledged.subtracting(refused).sorted())")
    }
}
