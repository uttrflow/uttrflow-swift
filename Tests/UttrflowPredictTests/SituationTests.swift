import Foundation
import Testing

@testable import UttrflowPredict

@Suite("Saying which situation a field is in")
struct SituationTests {
    @Test("A word naming a deployment is read as that deployment, however it is spelled.")
    func deploymentWords() {
        #expect(DeploymentEnvironment(word: "prod") == .production)
        #expect(DeploymentEnvironment(word: "PRODUCTION") == .production)
        #expect(DeploymentEnvironment(word: "prd") == .production)
        #expect(DeploymentEnvironment(word: "live") == .production)
        #expect(DeploymentEnvironment(word: "stg") == .staging)
        #expect(DeploymentEnvironment(word: "pre-prod") == .staging)
        #expect(DeploymentEnvironment(word: "qa") == .quality)
        #expect(DeploymentEnvironment(word: "uat") == .quality)
        #expect(DeploymentEnvironment(word: "qc") == .quality)
        #expect(DeploymentEnvironment(word: "dev") == .development)
        #expect(DeploymentEnvironment(word: "sandbox") == .development)
        #expect(DeploymentEnvironment(word: "localhost") == .local)
    }

    @Test("A word naming no deployment is refused rather than guessed at.")
    func unknownDeploymentWords() {
        #expect(DeploymentEnvironment(word: "orders_db") == nil)
        #expect(DeploymentEnvironment(word: "") == nil)
        #expect(DeploymentEnvironment(word: "productivity") == nil)
    }

    @Test("Every deployment survives being written down and read back.")
    func deploymentsAreStable() {
        for deployment in DeploymentEnvironment.allCases {
            #expect(DeploymentEnvironment(rawValue: deployment.rawValue) == deployment)
        }
    }

    @Test("Facets are lowercased and trimmed, so a tag written once matches a situation read later.")
    func facetsAreNormalised() {
        let situation = Situation(branch: "  Feat/Predict  ", connection: "Orders_DB", file: " App.swift ")
        #expect(situation.branch == "feat/predict")
        #expect(situation.connection == "orders_db")
        #expect(situation.file == "app.swift")
    }

    @Test("A blank facet is nothing said, not a facet whose value is blank.")
    func blankFacetsAreAbsent() {
        let situation = Situation(branch: "   ", connection: "")
        #expect(situation.branch == nil)
        #expect(situation.connection == nil)
        #expect(situation.isEmpty)
        #expect(Situation.unknown.isEmpty)
    }

    @Test("A situation that knows one thing is not empty.")
    func knowingOneThingIsEnough() {
        #expect(!Situation(environment: .production).isEmpty)
        #expect(!Situation(file: "app.swift").isEmpty)
    }

    @Test("A situation agrees completely with itself.")
    func agreesWithItself() {
        let situation = Situation(
            branch: "main", connection: "orders", environment: .quality, file: "app.swift")
        #expect(situation.similarity(to: situation) == 1)
    }

    @Test("Two situations that know nothing of each other are neither agreed nor opposed.")
    func ignoranceIsNeutral() {
        #expect(Situation.unknown.similarity(to: .unknown) == Situation.unknownAgreement)
        #expect(
            Situation(branch: "main").similarity(to: Situation(file: "app.swift"))
                == Situation.unknownAgreement)
    }

    @Test("Opposed deployments agree less than silent ones, and matching ones agree more.")
    func conflictRanksBelowSilence() {
        let here = Situation(environment: .quality)
        let opposed = Situation(environment: .production).similarity(to: here)
        let silent = Situation(branch: "main").similarity(to: here)
        let agreed = Situation(environment: .quality).similarity(to: here)
        #expect(opposed < silent)
        #expect(silent <= agreed)
        #expect(opposed >= 0)
    }

    @Test("Agreement is never negative, however completely two situations conflict.")
    func conflictBottomsOutAtZero() {
        let here = Situation(branch: "main", connection: "a", environment: .quality, file: "a.swift")
        let there = Situation(branch: "old", connection: "b", environment: .production, file: "b.swift")
        #expect(there.similarity(to: here) == 0)
    }

    @Test("Agreeing about the connection counts for more than agreeing about the open file.")
    func facetsAreWeighed() {
        let here = Situation(connection: "orders", file: "app.swift")
        let byConnection = Situation(connection: "orders", file: "other.swift").similarity(to: here)
        let byFile = Situation(connection: "other", file: "app.swift").similarity(to: here)
        #expect(byConnection > byFile)
    }

    @Test("A facet only one side knows is left out of the comparison rather than counted against it.")
    func silentFacetsAreLeftOut() {
        let here = Situation(connection: "orders", environment: .quality)
        #expect(Situation(environment: .quality).similarity(to: here) == 1)
        #expect(Situation(environment: .production).similarity(to: here) == 0)
    }

    @Test("A situation fills its gaps from another and keeps what it already knew.")
    func completionPrefersWhatIsKnown() {
        let tab = Situation(environment: .quality)
        let window = Situation(
            branch: "main", connection: "orders", environment: .production, file: "a.swift")
        let merged = tab.completed(by: window)
        #expect(merged.environment == .quality)
        #expect(merged.branch == "main")
        #expect(merged.connection == "orders")
        #expect(merged.file == "a.swift")
    }

    @Test("The same situation twice is one value, and hashes as one.")
    func situationsAreValues() {
        let first = Situation(connection: "orders", environment: .production)
        let second = Situation(connection: "orders", environment: .production)
        #expect(first == second)
        #expect(Set([first, second]).count == 1)
    }

    @Test("A situation survives being stored and read back, since it is a tag on every entry.")
    func situationRoundTrips() throws {
        let situation = Situation(
            branch: "feat/x", connection: "orders", environment: .quality, file: "a.swift")
        let encoded = try JSONEncoder().encode(situation)
        #expect(try JSONDecoder().decode(Situation.self, from: encoded) == situation)
    }

    @Test("Trimming leaves a string that was already trimmed alone.")
    func trimmingIsIdempotent() {
        #expect(trimmedWhitespace("main") == "main")
        #expect(trimmedWhitespace("  main \t ") == "main")
        #expect(trimmedWhitespace("   ") == "")
    }
}
