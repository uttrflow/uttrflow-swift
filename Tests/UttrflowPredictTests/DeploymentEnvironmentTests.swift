import Testing

@testable import UttrflowPredict

@Suite("Saying which deployment a word names")
struct DeploymentEnvironmentTests {
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
}
