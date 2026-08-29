import CryptoKit
import Foundation
import Testing

@testable import UttrflowAccount

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

    /// Every field the signature covers, one at a time. A verifier that happened to
    /// ignore the plan would hand out a paid subscription to anyone with a text editor,
    /// and one that ignored the expiry would make the backstop decorative.
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

    /// The two fields deliberately left outside the signature. Somebody who renames
    /// themselves at their provider must not be signed out for it, and neither field
    /// decides what anybody may do.
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

    /// A number nobody could have meant, of the kind that appears when somebody edits
    /// the file by hand. `Int(_: Double)` would trap on it and take the app down on
    /// launch; the entitlement must simply not be believed.
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

    /// The payload is a contract with a backend written in another language, so its
    /// shape is asserted rather than left to whatever the code happens to produce.
    @Test("covers exactly the agreed fields, each prefixed by its length")
    func payloadShape() throws {
        let entitlement = Entitlement(
            account: Fixture.account("u_1", provider: .gitHub), plan: .pro,
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000), signature: "ignored")
        let text = try #require(String(data: entitlement.signedPayload, encoding: .utf8))
        #expect(text == "uttrflow-entitlement-v1\n3:u_1\n6:gitHub\n3:pro\n10:1700000000")
    }

    /// The reason for length-prefixing. Two different entitlements must never produce
    /// the same bytes, however carefully an identifier is chosen to look like the
    /// field boundary that follows it.
    @Test("cannot be made to read one entitlement as another")
    func fieldsCannotImpersonateTheBoundary() {
        let sneaky = Fixture.entitlement(
            expiring: 86_400, plan: .free, account: Fixture.account("u_1\n6:gitHub\n3:pro"))
        let plain = Fixture.entitlement(expiring: 86_400, plan: .free, account: Fixture.account())
        #expect(sneaky.signedPayload != plain.signedPayload)
    }

    /// Whole seconds, because that is the only form a backend in another language can
    /// be relied upon to reproduce byte for byte.
    @Test("rounds a fractional expiry down to whole seconds")
    func expiryIsWholeSeconds() throws {
        let fractional = Entitlement(
            account: Fixture.account(), plan: .pro,
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000.75), signature: "")
        let text = try #require(String(data: fractional.signedPayload, encoding: .utf8))
        #expect(text.hasSuffix("10:1700000000"))
    }
}

@Suite("The public key a release build carries")
struct ReleaseVerifierTests {
    /// The key is real now, and what it must do is refuse everything it did not sign.
    ///
    /// It once had to be empty, and the test then said so. Both states have the same
    /// requirement — believe nothing that came from anywhere else — and only that
    /// requirement is worth asserting, because it is the one that holds either way.
    @Test("believes nothing it did not sign")
    func theReleaseKeyRefusesEverythingElse() {
        #expect(Ed25519EntitlementVerifier.releasePublicKeyBytes.count == 32)
        #expect(Ed25519EntitlementVerifier.release.isConfigured)
        #expect(Ed25519EntitlementVerifier.release.isAuthentic(Fixture.entitlement(expiring: 1)) == false)
        #expect(
            Ed25519EntitlementVerifier.release.isAuthentic(
                Fixture.entitlement(expiring: 1, signedBy: Fixture.impostor)) == false)
    }

    /// The trap the placeholder exists to avoid, asserted so that nobody "fixes" the
    /// empty constant by filling it with the obvious thing.
    ///
    /// Ed25519's all-zero public key decodes to a point of order four, and CryptoKit
    /// verifies without the cofactor. Against that key an all-zero signature satisfies
    /// the equation whenever the message's hash happens to land right, which is about
    /// one entitlement in four — so 32 zero bytes would not fail closed. It would hand
    /// a subscription to anybody willing to try their account identifier a few times,
    /// with a signature they could type out from memory.
    ///
    /// A batch rather than a single entitlement because one in four is a coin toss and
    /// this must not be a test that passes on Tuesdays. The identifiers are fixed, so
    /// the outcome is deterministic — just not predictable by reading it.
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
            CryptoKit no longer accepts an all-zero signature against the all-zero key. \
            That is good news, but read the reasoning in releasePublicKeyBytes before \
            relaxing anything: the placeholder must fail closed.
            """)
        #expect(
            Ed25519EntitlementVerifier.releasePublicKeyBytes != Data(repeating: 0, count: 32),
            "the release key must never be the all-zero key: it accepts a blank signature")
    }

    /// Bytes that are the wrong length are not a key either, and must be no more
    /// believed than none at all.
    @Test("believes nothing when handed something that is not a key")
    func rejectsMalformedKeyBytes() {
        let nonsense = Ed25519EntitlementVerifier(publicKeyBytes: Data([1, 2, 3]))
        #expect(nonsense.isAuthentic(Fixture.entitlement(expiring: 1)) == false)
    }
}
