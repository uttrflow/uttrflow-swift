import Foundation
import Testing

@testable import UttrflowPredict

@Suite("Saying which situation a field is in")
struct FieldSituationTests {
    @Test("Facets are lowercased and trimmed, so a tag written once matches a situation read later.")
    func facetsAreNormalised() {
        let situation = FieldSituation(
            branch: "  Feat/Predict  ", connection: "Orders_DB", file: " App.swift ")
        #expect(situation.branch == "feat/predict")
        #expect(situation.connection == "orders_db")
        #expect(situation.file == "app.swift")
    }

    @Test("A blank facet is nothing said, not a facet whose value is blank.")
    func blankFacetsAreAbsent() {
        let situation = FieldSituation(branch: "   ", connection: "")
        #expect(situation.branch == nil)
        #expect(situation.connection == nil)
        #expect(situation.isEmpty)
        #expect(FieldSituation.unknown.isEmpty)
    }

    @Test("A situation that knows one thing is not empty.")
    func knowingOneThingIsEnough() {
        #expect(!FieldSituation(environment: .production).isEmpty)
        #expect(!FieldSituation(file: "app.swift").isEmpty)
    }

    @Test("A situation agrees completely with itself.")
    func agreesWithItself() {
        let situation = FieldSituation(
            branch: "main", connection: "orders", environment: .quality, file: "app.swift")
        #expect(situation.similarity(to: situation) == 1)
    }

    @Test("Two situations that know nothing of each other are neither agreed nor opposed.")
    func ignoranceIsNeutral() {
        #expect(FieldSituation.unknown.similarity(to: .unknown) == FieldSituation.unknownAgreement)
        #expect(
            FieldSituation(branch: "main").similarity(to: FieldSituation(file: "app.swift"))
                == FieldSituation.unknownAgreement)
    }

    @Test("Opposed deployments agree less than silent ones, and matching ones agree more.")
    func conflictRanksBelowSilence() {
        let here = FieldSituation(environment: .quality)
        let opposed = FieldSituation(environment: .production).similarity(to: here)
        let silent = FieldSituation(branch: "main").similarity(to: here)
        let agreed = FieldSituation(environment: .quality).similarity(to: here)
        #expect(opposed < silent)
        #expect(silent <= agreed)
        #expect(opposed >= 0)
    }

    @Test("Agreement is never negative, however completely two situations conflict.")
    func conflictBottomsOutAtZero() {
        let here = FieldSituation(
            branch: "main", connection: "a", environment: .quality, file: "a.swift")
        let there = FieldSituation(
            branch: "old", connection: "b", environment: .production, file: "b.swift")
        #expect(there.similarity(to: here) == 0)
    }

    @Test("Agreeing about the connection counts for more than agreeing about the open file.")
    func facetsAreWeighed() {
        let here = FieldSituation(connection: "orders", file: "app.swift")
        let byConnection = FieldSituation(connection: "orders", file: "other.swift").similarity(to: here)
        let byFile = FieldSituation(connection: "other", file: "app.swift").similarity(to: here)
        #expect(byConnection > byFile)
    }

    @Test("A facet only one side knows is left out of the comparison rather than counted against it.")
    func silentFacetsAreLeftOut() {
        let here = FieldSituation(connection: "orders", environment: .quality)
        #expect(FieldSituation(environment: .quality).similarity(to: here) == 1)
        #expect(FieldSituation(environment: .production).similarity(to: here) == 0)
    }

    @Test("A situation fills its gaps from another and keeps what it already knew.")
    func completionPrefersWhatIsKnown() {
        let tab = FieldSituation(environment: .quality)
        let window = FieldSituation(
            branch: "main", connection: "orders", environment: .production, file: "a.swift")
        let merged = tab.completed(by: window)
        #expect(merged.environment == .quality)
        #expect(merged.branch == "main")
        #expect(merged.connection == "orders")
        #expect(merged.file == "a.swift")
    }

    @Test("The same situation twice is one value, and hashes as one.")
    func situationsAreValues() {
        let first = FieldSituation(connection: "orders", environment: .production)
        let second = FieldSituation(connection: "orders", environment: .production)
        #expect(first == second)
        #expect(Set([first, second]).count == 1)
    }

    @Test("A situation survives being stored and read back, since it is a tag on every entry.")
    func situationRoundTrips() throws {
        let situation = FieldSituation(
            branch: "feat/x", connection: "orders", environment: .quality, file: "a.swift")
        let encoded = try JSONEncoder().encode(situation)
        #expect(try JSONDecoder().decode(FieldSituation.self, from: encoded) == situation)
    }
}
