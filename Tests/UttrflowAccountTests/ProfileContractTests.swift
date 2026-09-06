import Foundation
import Testing

@testable import UttrflowAccount

/// Decodes the `/v1/me` document the backend's own route function composes into `fixtures/profile.json`.
@Suite(
    "The /v1/me contract with uttrflow-backend",
    .enabled(if: BackendCheckout.isPresent, BackendCheckout.absenceReason))
struct ProfileContractTests {
    /// The fixture file's shape.
    private struct Fixture: Decodable {
        /// The key that signed the entitlement inside `profile`.
        let publicKeyBase64: String
        /// The backend's note on how the file is produced.
        let note: String
        /// The document under test.
        let profile: Profile
    }

    /// The fixture, or an error: no backend is a skip, but no fixture beside a present backend is a failure.
    private func loadFixture() throws -> Fixture {
        let path = try #require(
            BackendCheckout.fixture("profile.json"),
            "the suite ran without a backend checkout, which .enabled(if:) should have prevented")
        let data = try #require(
            FileManager.default.contents(atPath: path.path),
            """
            uttrflow-backend is checked out but \(path.path) is missing. \
            Run `node scripts/generate-fixtures.ts` there.
            """)
        return try JSONDecoder().decode(Fixture.self, from: data)
    }

    @Test("decodes the document the backend composes, field for field")
    func decodesTheRealDocument() throws {
        let fixture = try loadFixture()
        let profile = fixture.profile

        #expect(profile.account.identifier == "acc_0f0c1a5e6b4d4f0f9a1b2c3d4e5f6071")
        #expect(profile.account.displayName == "Naveen Bhatt")
        #expect(profile.account.provider == .google)
        // A path on our own API, never the provider's address: the backend does not send one.
        #expect(profile.account.avatarPath == "/v1/me/avatar")
        #expect(profile.entitlement.account.avatarPath == nil, "the signed half names no picture")

        #expect(profile.subscription.plan == .pro)
        // The spelling with the underscore, which a hand-written enum gets wrong.
        #expect(profile.subscription.status == .pastDue)
        #expect(profile.subscription.effectivePlan == .pro)
        #expect(profile.subscription.limits.monthlyMinutes == nil, "null means unlimited, not zero")

        #expect(profile.devices.count == 2)
        #expect(profile.devices.first?.platform == .macOS)
        #expect(profile.devices.first?.isCurrent == true)
        #expect(profile.currentDevice?.name == "Naveen's MacBook Pro")
        #expect(profile.devices.last?.platform == .iOS)
        #expect(profile.devices.last?.appVersion == nil)
        #expect(profile.devices.last?.isCurrent == false)
    }

    /// `fetchedAt` is ISO-8601 with milliseconds and `expiresAt` seconds since 2001; both are pinned exactly.
    @Test("reads the ISO timestamps and the signed reference-date number")
    func readsBothDateEncodings() throws {
        let fixture = try loadFixture()

        #expect(fixture.profile.fetchedAt == Date(timeIntervalSince1970: 1_787_822_441))
        #expect(
            fixture.profile.subscription.currentPeriodEnd
                == Date(timeIntervalSince1970: 1_803_902_400))
        #expect(
            fixture.profile.entitlement.expiresAt == Date(timeIntervalSince1970: 1_803_902_400))
    }

    @Test("believes the entitlement inside it, using the app's own verifier")
    func verifiesTheEntitlement() throws {
        let fixture = try loadFixture()
        let key = try #require(Data(base64Encoded: fixture.publicKeyBase64))
        let verifier = Ed25519EntitlementVerifier(publicKeyBytes: key)

        #expect(verifier.isAuthentic(fixture.profile.entitlement))
        #expect(fixture.profile.isInternallyConsistent)
    }

    /// A platform added after this build shipped must cost an unfamiliar icon, not the account page.
    @Test("survives a platform it has never heard of")
    func unknownPlatformsDegrade() throws {
        let json = Data(#"["macos","visionos","web"]"#.utf8)
        let platforms = try JSONDecoder().decode([Profile.Platform].self, from: json)
        #expect(platforms == [.macOS, .unrecognised, .web])
    }
}
