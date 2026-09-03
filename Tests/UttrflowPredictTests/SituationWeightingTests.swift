import Testing

@testable import UttrflowPredict

@Suite("Preferring the entries this situation calls for")
struct SituationWeightingTests {
    @Test("A candidate tagged with the situation the user is in is lifted.")
    func agreementLifts() {
        let here = Situation(connection: "orders_qa", environment: .quality)
        #expect(SituationWeighting.weight(for: here, in: here) == 1 + SituationWeighting.agreementLift)
    }

    @Test("A candidate tagged with a conflicting situation is lowered, but never out of sight.")
    func conflictLowers() {
        let here = Situation(connection: "orders_qa", environment: .quality)
        let there = Situation(connection: "orders_prod", environment: .production)
        let weight = SituationWeighting.weight(for: there, in: here)
        #expect(weight == 1 - SituationWeighting.conflictDrop)
        #expect(weight > 0)
    }

    @Test("A candidate with no tag at all is neither lifted nor lowered.")
    func anUntaggedCandidateIsNeutral() {
        let here = Situation(environment: .quality)
        #expect(SituationWeighting.weight(for: nil, in: here) == 1)
        #expect(SituationWeighting.weight(for: .unknown, in: here) == 1)
    }

    @Test("A user in no particular situation prefers nothing, whatever the tags say.")
    func knowingNothingPrefersNothing() {
        #expect(SituationWeighting.weight(for: Situation(environment: .production), in: .unknown) == 1)
    }

    @Test("A stale tag that only partly agrees still counts for something.")
    func partialAgreementIsWeak() {
        let here = Situation(branch: "main", connection: "orders_qa", environment: .quality)
        let stale = Situation(branch: "feat/old", connection: "orders_qa", environment: .quality)
        let weight = SituationWeighting.weight(for: stale, in: here)
        #expect(weight > 1)
        #expect(weight < 1 + SituationWeighting.agreementLift)
    }

    @Test("A tag can never take a candidate's score to nothing, so no entry is hidden by one.")
    func nothingIsEverHidden() {
        let here = Situation(branch: "main", connection: "a", environment: .quality, file: "a.swift")
        let there = Situation(branch: "old", connection: "b", environment: .production, file: "b.swift")
        let alone = Frecency.score(remembered("select * from orders"), now: now)
        let weighted = SituationWeighting.score(
            remembered("select * from orders"), tagged: there, in: here, now: now)
        #expect(weighted > 0)
        #expect(weighted < alone)
    }

    @Test("The situation multiplies the evidence rather than replacing it.")
    func evidenceStillDecides() {
        let here = Situation(environment: .quality)
        let strong = SituationWeighting.score(remembered("a", count: 40), tagged: nil, in: here, now: now)
        let weak = SituationWeighting.score(remembered("b", count: 2), tagged: here, in: here, now: now)
        #expect(strong > weak)
    }

    @Test("Between two candidates the corpus likes equally, the situation decides.")
    func theSituationBreaksTheTie() {
        let here = Situation(connection: "orders_qa", environment: .quality)
        let there = Situation(connection: "orders_prod", environment: .production)
        let ordered = SituationWeighting.ordered(
            [(remembered("prod-first"), there), (remembered("qa-first"), here)], in: here, now: now)
        #expect(ordered.map(\.text) == ["qa-first", "prod-first"])
    }

    @Test("Candidates the situation cannot separate keep a stable order.")
    func tiesAreBrokenByName() {
        let here = Situation(environment: .quality)
        let ordered = SituationWeighting.ordered(
            [(remembered("b"), nil), (remembered("a"), nil)], in: here, now: now)
        #expect(ordered.map(\.text) == ["a", "b"])
    }

    @Test("A candidate the environment supplied is weighed by its tag like any other.")
    func environmentCandidatesAreWeighedToo() {
        let here = Situation(environment: .quality)
        let candidate = Candidate(text: "orders_qa", source: .environment)
        let matched = SituationWeighting.score(candidate, tagged: here, in: here, now: now)
        let unmatched = SituationWeighting.score(candidate, tagged: nil, in: here, now: now)
        #expect(matched > unmatched)
    }
}
