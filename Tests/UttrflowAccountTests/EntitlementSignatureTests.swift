// Tests for Ed25519EntitlementVerifier: the signed payload, tampering, and the release key.

import CryptoKit
import Foundation
import Testing

@testable import UttrflowAccount

/// What the verifier believes, what it refuses, and the exact bytes a signature covers.
@Suite("Trusting a cached entitlement")
struct EntitlementSignatureTests {
    @Test("believes what the backend signed")
    func acceptsAGenuineSignature() {
        #expect(Fixture.verifier.isAuthentic(Fixture.entitlement(expiring: 86_400)))
    }

    @Test("believes nothing anybody else signed")
    func rejectsAnotherKeysSignature() {
        #expect(
            Fixture.verifier.isAuthentic(
                Fixture.entitlement(expiring: 86_400, signedBy: Fixture.impostor)) == false)
    }

    /// Every covered field altered one at a time; a verifier ignoring any of them is a forgery oracle.
    @Test("rejects an entitlement whose covered fields were altered after signing")
    func rejectsTampering() {
        let genuine = Fixture.entitlement(expiring: 86_400, plan: .free)
        let alterations = [
            Entitlement(
                account: genuine.account, plan: .pro, expiresAt: genuine.expiresAt,
                signature: genuine.signature),
            Entitlement(
                account: genuine.account, plan: genuine.plan,
                expiresAt: genuine.expiresAt.addingTimeInterval(86_400),
                signature: genuine.signature),
            Entitlement(
                account: Fixture.account("somebody_else"), plan: genuine.plan,
                expiresAt: genuine.expiresAt, signature: genuine.signature),
            Entitlement(
                account: Fixture.account(provider: .apple), plan: genuine.plan,
                expiresAt: genuine.expiresAt, signature: genuine.signature),
        ]
        for altered in alterations {
            #expect(Fixture.verifier.isAuthentic(altered) == false, "accepted \(altered)")
        }
    }

    /// Display name and email are outside the signature, so a rename at the provider is not a sign-out.
    @Test("keeps believing an entitlement after the user renames themselves")
    func toleratesADisplayNameChange() {
        let genuine = Fixture.entitlement(expiring: 86_400)
        let renamed = Entitlement(
            account: Account(
                identifier: genuine.account.identifier, displayName: "Naveen B",
                emailAddress: "new@example.com", provider: genuine.account.provider),
            plan: genuine.plan, expiresAt: genuine.expiresAt, signature: genuine.signature)
        #expect(Fixture.verifier.isAuthentic(renamed))
    }

    @Test("rejects a signature that is not even base64")
    func rejectsNonsenseSignature() {
        let genuine = Fixture.entitlement(expiring: 86_400)
        let mangled = Entitlement(
            account: genuine.account, plan: genuine.plan, expiresAt: genuine.expiresAt,
            signature: "not a signature at all")
        #expect(Fixture.verifier.isAuthentic(mangled) == false)
    }

    /// A hand-edited expiry that `Int(_: Double)` would trap on must simply not be believed.
    @Test("rejects an unrepresentable expiry instead of trapping on it")
    func survivesAnAbsurdExpiry() {
        for seconds in [TimeInterval.infinity, -.infinity, .nan, 1e300] {
            let absurd = Entitlement(
                account: Fixture.account(), plan: .pro,
                expiresAt: Date(timeIntervalSince1970: seconds), signature: "")
            #expect(!absurd.signedPayload.isEmpty)
            #expect(Fixture.verifier.isAuthentic(absurd) == false)
        }
    }

    /// The payload is a contract with a backend in another language, so its shape is asserted exactly.
    @Test("covers exactly the agreed fields, each prefixed by its length")
    func payloadShape() throws {
        let entitlement = Entitlement(
            account: Fixture.account("u_1", provider: .gitHub), plan: .pro,
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000), signature: "ignored")
        let text = try #require(String(data: entitlement.signedPayload, encoding: .utf8))
        #expect(text == "uttrflow-entitlement-v1\n3:u_1\n6:gitHub\n3:pro\n10:1700000000")
    }

    /// Length-prefixing means no identifier can be chosen to look like the field boundary after it.
    @Test("cannot be made to read one entitlement as another")
    func fieldsCannotImpersonateTheBoundary() {
        let sneaky = Fixture.entitlement(
            expiring: 86_400, plan: .free, account: Fixture.account("u_1\n6:gitHub\n3:pro"))
        let plain = Fixture.entitlement(expiring: 86_400, plan: .free, account: Fixture.account())
        #expect(sneaky.signedPayload != plain.signedPayload)
    }

    /// Whole seconds are the only form a backend in another language reproduces byte for byte.
    @Test("rounds a fractional expiry down to whole seconds")
    func expiryIsWholeSeconds() throws {
        let fractional = Entitlement(
            account: Fixture.account(), plan: .pro,
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000.75), signature: "")
        let text = try #require(String(data: fractional.signedPayload, encoding: .utf8))
        #expect(text.hasSuffix("10:1700000000"))
    }
}

/// The key compiled into a release build, and the degenerate key it must never be.
@Suite("The public key a release build carries")
struct ReleaseVerifierTests {
    /// The release key is real, and refuses everything it did not sign.
    @Test("believes nothing it did not sign")
    func theReleaseKeyRefusesEverythingElse() {
        #expect(Ed25519EntitlementVerifier.releasePublicKeyBytes.count == 32)
        #expect(Ed25519EntitlementVerifier.release.isConfigured)
        #expect(Ed25519EntitlementVerifier.release.isAuthentic(Fixture.entitlement(expiring: 1)) == false)
        #expect(
            Ed25519EntitlementVerifier.release.isAuthentic(
                Fixture.entitlement(expiring: 1, signedBy: Fixture.impostor)) == false)
    }

    /// The all-zero key accepts a blank signature one time in four, hence a batch; see Docs/entitlements.md.
    @Test("rejects the degenerate key that would accept a forgery")
    func rejectsTheDegenerateKeyThatWouldAcceptAForgery() {
        let zeroes = Ed25519EntitlementVerifier(publicKeyBytes: Data(repeating: 0, count: 32))
        let blankSignature = Data(repeating: 0, count: 64).base64EncodedString()
        let forgeries = (0..<64).map { index in
            Entitlement(
                account: Fixture.account("u_\(index)"), plan: .pro, expiresAt: Fixture.noon,
                signature: blankSignature)
        }

        #expect(
            forgeries.contains(where: zeroes.isAuthentic),
            """
            CryptoKit rejects a blank signature against the all-zero key. That is good news, but \
            read Docs/entitlements.md before relaxing anything: the placeholder must fail closed.
            """)
        #expect(
            Ed25519EntitlementVerifier.releasePublicKeyBytes != Data(repeating: 0, count: 32),
            "the release key must never be the all-zero key: it accepts a blank signature")
    }

    /// Bytes of the wrong length are not a key, and are believed no more than none at all.
    @Test("believes nothing when handed something that is not a key")
    func rejectsMalformedKeyBytes() {
        let nonsense = Ed25519EntitlementVerifier(publicKeyBytes: Data([1, 2, 3]))
        #expect(nonsense.isAuthentic(Fixture.entitlement(expiring: 1)) == false)
    }
}
