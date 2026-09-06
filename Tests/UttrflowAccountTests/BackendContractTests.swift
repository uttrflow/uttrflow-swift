import Foundation
import Testing

@testable import UttrflowAccount

/// Runs the app's verifier over bytes the backend signs; each side's own tests cannot see a disagreement.
@Suite(
    "The contract with uttrflow-backend",
    .enabled(if: BackendCheckout.isPresent, BackendCheckout.absenceReason))
struct BackendContractTests {
    /// The fixture file's shape.
    private struct Fixture: Decodable {
        /// One signed entitlement and the verdict the backend expects for it.
        struct Case: Decodable {
            /// The case's label.
            let name: String
            /// `"valid"`, or the reason it is not.
            let expectation: String
            /// The entitlement under test.
            let entitlement: Entitlement
        }
        /// The key that signed every valid case.
        let publicKeyBase64: String
        /// The signed payload's lines, for the valid case.
        let canonicalForm: [String]
        /// Every case, valid and not.
        let cases: [Case]
    }

    /// The fixture, or an error: no backend is a skip, but no fixture beside a present backend is a failure.
    private func loadFixture() throws -> Fixture {
        let path = try #require(
            BackendCheckout.fixture("entitlements.json"),
            "the suite ran without a backend checkout, which .enabled(if:) should have prevented")
        let data = try #require(
            FileManager.default.contents(atPath: path.path),
            """
            uttrflow-backend is checked out but \(path.path) is missing. \
            Run `node scripts/generate-fixtures.ts` there.
            """)
        return try JSONDecoder().decode(Fixture.self, from: data)
    }

    /// Every case, judged by the app's own verifier rather than a copy of it.
    @Test("verifies exactly the cases the backend says are valid")
    func agreesWithTheBackend() throws {
        let fixture = try loadFixture()
        let key = try #require(
            Data(base64Encoded: fixture.publicKeyBase64), "the fixture's public key is not base64")
        let verifier = Ed25519EntitlementVerifier(publicKeyBytes: key)

        for testCase in fixture.cases {
            let accepted = verifier.isAuthentic(testCase.entitlement)
            #expect(
                accepted == (testCase.expectation == "valid"),
                "\(testCase.name): app said \(accepted), backend said \(testCase.expectation)")
        }
    }

    /// The bytes themselves, so a mismatch names the field rather than just failing.
    @Test("builds byte-for-byte the payload the backend signed")
    func canonicalFormMatches() throws {
        let fixture = try loadFixture()
        let valid = try #require(
            fixture.cases.first(where: { $0.expectation == "valid" }),
            "the fixture has no valid case, so there is no canonical form to compare")

        let ours = String(decoding: valid.entitlement.signedPayload, as: UTF8.self)
        #expect(ours == fixture.canonicalForm.joined(separator: "\n"))
    }
}
