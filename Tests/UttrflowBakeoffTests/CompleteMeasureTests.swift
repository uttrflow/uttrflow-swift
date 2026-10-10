import ArgumentParser
import Foundation
import Testing
@testable import uttrflow_bakeoff
@testable import UttrflowEval
@testable import UttrflowPredict

/// A generator that throws on every call, so the measurement is asked to judge a pass that never produced one.
private struct ThrowingGenerator: CandidateGenerating {
    var isReady: Bool { true }
    func completions(for typed: String, in situation: GenerationSituation) async throws -> [String] {
        throw GeneratorError.broken
    }
    func alternatives(
        for typed: String, in situation: GenerationSituation, excluding leader: String
    ) async throws -> [String] {
        throw GeneratorError.broken
    }
    enum GeneratorError: Error { case broken }
}

/// A generator that answers nothing, the silence-equivalent of a refusal, to prove the throw is what fails the fixture, not the empty list.
private struct SilentGenerator: CandidateGenerating {
    var isReady: Bool { true }
    func completions(for typed: String, in situation: GenerationSituation) async throws -> [String] {
        []
    }
    func alternatives(
        for typed: String, in situation: GenerationSituation, excluding leader: String
    ) async throws -> [String] {
        []
    }
}

struct CompleteMeasureTests {
    @Test("A fixture report records whether the default catalogue ran in full.")
    func fixtureReportCarriesFullCatalogueProvenance() throws {
        let result = FixtureResult(
            name: "test/complete", category: "test", typed: "hello", hit: true, judged: true,
            conforms: true, elapsedMs: 1, first: "hello", drawn: ["hello"], raw: nil, invented: false)
        let report = FixtureReport(
            results: [result], fixtureCatalogueCount: 1, fullFixtureCatalogue: true)
        let encoded = try JSONEncoder().encode(report)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["fixtureCatalogueCount"] as? Int == 1)
        #expect(object["fullFixtureCatalogue"] as? Bool == true)
    }

    @Test("A throwing generator on a silence fixture is a miss, not a hit.")
    func throwingGeneratorMissesSilenceFixture() async throws {
        let silence = CompletionExpectation(acceptable: [CompletionExpectation.nothing], band: 1...40)
        let fixture = Fixture(
            "test/silence", GenerationSituation(application: "Terminal"), typed: "git status",
            expectation: silence)
        let (results, errorCount) = await Complete.measure(
            fixtures: [fixture], generator: ThrowingGenerator(), sources: false)
        #expect(results.count == 1)
        #expect(errorCount == 1)
        #expect(results[0].hit == false)
        #expect(results[0].conforms == false)
        #expect(results[0].error != nil)
    }

    @Test("A silent generator on a silence fixture is a hit, since the fixture got the answer it expected.")
    func silentGeneratorHitsSilenceFixture() async throws {
        let silence = CompletionExpectation(acceptable: [CompletionExpectation.nothing], band: 1...40)
        let fixture = Fixture(
            "test/silence", GenerationSituation(application: "Terminal"), typed: "git status",
            expectation: silence)
        let (results, errorCount) = await Complete.measure(
            fixtures: [fixture], generator: SilentGenerator(), sources: false)
        #expect(results.count == 1)
        #expect(errorCount == 0)
        #expect(results[0].hit == true)
        #expect(results[0].conforms == true)
        #expect(results[0].error == nil)
    }
}
