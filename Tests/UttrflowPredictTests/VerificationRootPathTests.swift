// Tests what the machine is asked about a path directly under the root directory, and a name that differs only in case.
import Testing

@testable import UttrflowPredict

@Suite("Verification of paths at the root")
struct VerificationRootPathTests {
    @Test("a word that is the root alone is open at a name not yet begun, so the root is listed")
    func rootAloneListsTheRoot() throws {
        let token = try #require(CompletionToken("cd /"))
        #expect(
            Verification.choices(for: token)
                == Verification.Attestation(lookups: [
                    Verification.Lookup("", [.directories(under: "/")], prefix: "/")
                ]))
    }

    @Test("a name directly under the root is looked up in the root, with the root as the prefix")
    func nameUnderTheRoot() throws {
        let token = try #require(CompletionToken("cat /et"))
        #expect(
            Verification.attestation(for: token)?.lookups == [
                Verification.Lookup("et", [.entries(under: "/")], prefix: "/")
            ])
    }

    @Test("a name that differs from a known one only in case is never corrected to it")
    func caseOnlyIsNotATypo() {
        #expect(Verification.nearestNeighbour(of: "readme", among: ["README"]) == nil)
        #expect(
            Verification.nearestNeighbour(of: "readme", among: ["README"], caseSensitive: true) == "README")
    }
}
