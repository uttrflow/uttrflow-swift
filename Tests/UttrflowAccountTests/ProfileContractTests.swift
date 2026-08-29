import Foundation
import Testing

@testable import UttrflowAccount

/// Checks the app's decoder against the document the backend really composes.
///
/// A sibling of ``BackendContractTests``, and here for the same reason: that suite proves
/// the two sides agree about the bytes a signature covers, and this one proves they agree
/// about the document those bytes travel in. Which is where a contract of this shape
/// actually breaks — a status spelled `past_due`, a timestamp with milliseconds, a
/// platform this build has never heard of, and one document carrying two date encodings
/// at once because the signed part cannot change shape.
///
/// The fixture is written by `npm run` on the backend side, by calling the same function
/// its route calls. A field renamed there fails here.
@Suite(
    "The /v1/me contract with uttrflow-backend",
    .enabled(if: BackendCheckout.isPresent, BackendCheckout.absenceReason))
struct ProfileContractTests {
    private struct Fixture: Decodable {
        let publicKeyBase64: String
        let note: String
        let profile: Profile
    }

    /// The fixture the backend emits, or an error naming what is wrong with it.
    ///
    /// This suite already drew the right distinction — a missing backend is a skip, a
    /// missing fixture *beside* a present backend is an error — and it kept it while the
    /// older suite did not. What it could not do was say out loud that it had skipped, and
    /// it was locating the checkout by counting `..`, which is wrong from every worktree.
    /// ``BackendCheckout`` fixes both; the distinction below is unchanged.
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
        // A path on our own API, never the provider's address. The backend deliberately
        // does not send the second, and an app that started expecting one would be the
        // reason it had to.
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

    /// Both date encodings, in one document, decoded correctly.
    ///
    /// `fetchedAt` is an ISO-8601 string with milliseconds; `expiresAt` inside the
    /// entitlement is a number of seconds since 2001. Getting either wrong is silent — a
    /// date thirty-one years out looks like a date — so both are pinned to an instant
    /// written here in full.
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

    /// The app will one day be older than the service it talks to. A device on a platform
    /// added after this build shipped must cost an unfamiliar icon, not the account page.
    @Test("survives a platform it has never heard of")
    func unknownPlatformsDegrade() throws {
        let json = Data(#"["macos","visionos","web"]"#.utf8)
        let platforms = try JSONDecoder().decode([Profile.Platform].self, from: json)
        #expect(platforms == [.macOS, .unrecognised, .web])
    }
}
