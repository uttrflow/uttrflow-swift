import ArgumentParser
import Testing
import UttrflowPredict
@testable import uttrflow_bakeoff

@Suite("Completion fixtures retain their denominator when a source retires")
struct RetiredSourceFixtureTests {
    @Test("A learned command uses entered-history evidence in the unchanged source sample")
    func learnedCommandUsesPersonalEvidence() throws {
        let fixtures = SourceFixtures.all
        let command = try #require(fixtures.first { $0.typed == "git " })
        #expect(fixtures.count == 3)
        #expect(command.name == "source/learned-command")
        #expect(command.seededCandidates.map(\.source) == [.personal])
        #expect(command.seededCandidates.map(\.evidence?.text) == ["git commit"])
        #expect(command.seededCandidates.map(\.evidence?.count) == [10])
    }

    @Test("A retired fixture fingerprint rejects comparison without shrinking precision")
    func historicalIdentityCannotCompare() throws {
        let fixtures = SourceFixtures.all
        let command = try #require(fixtures.first { $0.typed == "git " })
        let retiredIdentity = "7a0745b4a191"
        #expect(command.identity != retiredIdentity)
        let retainedName = Fixture(
            "source/succession", command.situation, typed: command.typed,
            expectation: command.expectation, machine: command.machine,
            seededCandidates: command.seededCandidates)
        #expect(retainedName.identity != retiredIdentity)
        let current = FixtureReport(results: try fixtures.map { try result($0, identity: $0.identity) })
        let historical = FixtureReport(
            results: try fixtures.map {
                try result($0, identity: $0.typed == "git " ? retiredIdentity : $0.identity)
            })
        #expect(current.summary.total == 3)
        #expect(current.summary.shown == 3)
        #expect(historical.summary.total == current.summary.total)
        #expect(historical.summary.shown == current.summary.shown)
        #expect(throws: ValidationError.self) {
            try Complete.requireNoRegression(current, against: historical)
        }
        try Complete.requireNoRegression(current, against: current)
    }

    private func result(_ fixture: Fixture, identity: String) throws -> FixtureResult {
        let answer = fixture.typed + (try #require(fixture.expectation.acceptable.first))
        return FixtureResult(
            name: fixture.name, category: "source", typed: fixture.typed,
            hit: fixture.hits([answer]), judged: fixture.isJudged,
            conforms: fixture.conforms([answer]), elapsedMs: 1,
            first: answer, drawn: [answer], raw: nil, invented: false, fixtureIdentity: identity)
    }

}
