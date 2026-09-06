import Testing

@testable import UttrflowPredict

@Suite("Preferring the entries this situation calls for")
struct FieldSituationWeightingTests {
    @Test("A candidate tagged with the situation the user is in is lifted.")
    func agreementLifts() {
        let here = FieldSituation(connection: "orders_qa", environment: .quality)
        #expect(
            FieldSituationWeighting.weight(for: here, in: here)
                == 1 + FieldSituationWeighting.agreementLift)
    }

    @Test("A candidate tagged with a conflicting situation is lowered, but never out of sight.")
    func conflictLowers() {
        let here = FieldSituation(connection: "orders_qa", environment: .quality)
        let there = FieldSituation(connection: "orders_prod", environment: .production)
        let weight = FieldSituationWeighting.weight(for: there, in: here)
        #expect(weight == 1 - FieldSituationWeighting.conflictDrop)
        #expect(weight > 0)
    }

    @Test("A candidate with no tag at all is neither lifted nor lowered.")
    func anUntaggedCandidateIsNeutral() {
        let here = FieldSituation(environment: .quality)
        #expect(FieldSituationWeighting.weight(for: nil, in: here) == 1)
        #expect(FieldSituationWeighting.weight(for: .unknown, in: here) == 1)
    }

    @Test("A user in no particular situation prefers nothing, whatever the tags say.")
    func knowingNothingPrefersNothing() {
        #expect(
            FieldSituationWeighting.weight(for: FieldSituation(environment: .production), in: .unknown)
                == 1)
    }

    @Test("A stale tag that only partly agrees still counts for something.")
    func partialAgreementIsWeak() {
        let here = FieldSituation(branch: "main", connection: "orders_qa", environment: .quality)
        let stale = FieldSituation(branch: "feat/old", connection: "orders_qa", environment: .quality)
        let weight = FieldSituationWeighting.weight(for: stale, in: here)
        #expect(weight > 1)
        #expect(weight < 1 + FieldSituationWeighting.agreementLift)
    }

    @Test("A tag can never take a candidate's score to nothing, so no entry is hidden by one.")
    func nothingIsEverHidden() {
        let here = FieldSituation(
            branch: "main", connection: "a", environment: .quality, file: "a.swift")
        let there = FieldSituation(
            branch: "old", connection: "b", environment: .production, file: "b.swift")
        let alone = Frecency.score(remembered("select * from orders"), now: moment)
        let weighted = FieldSituationWeighting.score(
            remembered("select * from orders"), tagged: there, in: here, now: moment)
        #expect(weighted > 0)
        #expect(weighted < alone)
    }

    @Test("The situation multiplies the evidence rather than replacing it.")
    func evidenceStillDecides() {
        let here = FieldSituation(environment: .quality)
        let strong = FieldSituationWeighting.score(
            remembered("a", count: 40), tagged: nil, in: here, now: moment)
        let weak = FieldSituationWeighting.score(
            remembered("b", count: 2), tagged: here, in: here, now: moment)
        #expect(strong > weak)
    }

    @Test("Between two candidates the corpus likes equally, the situation decides.")
    func theSituationBreaksTheTie() {
        let here = FieldSituation(connection: "orders_qa", environment: .quality)
        let there = FieldSituation(connection: "orders_prod", environment: .production)
        let matching = FieldSituationWeighting.score(
            remembered("qa-first"), tagged: here, in: here, now: moment)
        let conflicting = FieldSituationWeighting.score(
            remembered("prod-first"), tagged: there, in: here, now: moment)
        #expect(matching > conflicting)
    }

    @Test("A candidate the environment supplied is weighed by its tag like any other.")
    func environmentCandidatesAreWeighedToo() {
        let here = FieldSituation(environment: .quality)
        let candidate = Candidate(text: "orders_qa", source: .environment)
        let matched = FieldSituationWeighting.score(candidate, tagged: here, in: here, now: moment)
        let unmatched = FieldSituationWeighting.score(candidate, tagged: nil, in: here, now: moment)
        #expect(matched > unmatched)
    }
}
