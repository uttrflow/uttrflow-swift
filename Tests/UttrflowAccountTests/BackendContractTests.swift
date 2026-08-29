import Foundation
import Testing

@testable import UttrflowAccount

/// Checks the app against the real fixture the backend emits.
///
/// This suite exists because the two sides once disagreed in silence. The service signed
/// six fields with a millisecond expiry while the app verified four with a second expiry,
/// so no entitlement it ever issued could have verified — and every test on both sides
/// passed, because each was checking its own idea of the contract against itself. Only
/// running one side's verifier over the other side's bytes finds that.
@Suite(
    "The contract with uttrflow-backend",
    .enabled(if: BackendCheckout.isPresent, BackendCheckout.absenceReason))
struct BackendContractTests {
    private struct Fixture: Decodable {
        struct Case: Decodable {
            let name: String
            let expectation: String
            let entitlement: Entitlement
        }
        let publicKeyBase64: String
        let canonicalForm: [String]
        let cases: [Case]
    }

    /// The fixture, or an error naming what is wrong with it.
    ///
    /// The suite as a whole is skipped when there is no backend at all — that is the
    /// `.enabled(if:)` above, and it is reported. So by the time this runs the checkout
    /// exists, and a missing or unreadable fixture inside it is a real failure rather than
    /// another reason to go quiet.
    ///
    /// That distinction is the entire point. This used to return `nil` for both "no
    /// sibling checkout" and "the path is wrong", which made a dead suite and a skipped
    /// one identical — and it had already sat dead for days once, behind a hardcoded home
    /// directory. ``BackendCheckout`` finds the checkout by searching upward rather than
    /// counting `..`, because counting was wrong from every worktree.
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
