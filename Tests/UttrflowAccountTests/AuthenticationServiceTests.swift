import CryptoKit
import Foundation
import UttrflowCore
import Testing

@testable import UttrflowAccount

/// The in-memory service the development app signs in against, rehearsing the release build's flow.
@Suite("Signing in against a backend that is not there yet")
struct InMemoryAuthenticationServiceTests {
    /// A service signing with the test backend's key, at noon.
    private func service(
        plan: Plan = .pro, lifetime: TimeInterval = 3_600
    ) -> InMemoryAuthenticationService {
        InMemoryAuthenticationService(
            plan: plan, lifetime: lifetime, signingKey: Fixture.backend, now: { Fixture.noon })
    }

    /// The whole exchange, in the shape the release build uses it.
    @Test("hands back a challenge, waits for it, and mints a signed profile")
    func fullExchange() async throws {
        let service = service()
        let challenge = try await service.beginSignIn(with: .gitHub)
        let profile = try await service.completeSignIn(challenge)

        #expect(profile.entitlement.plan == .pro)
        #expect(profile.entitlement.expiresAt == Fixture.noon.addingTimeInterval(3_600))
        #expect(Fixture.verifier.isAuthentic(profile.entitlement))
        // The unsigned half agrees with the signed one, which is what the cache checks.
        #expect(profile.isInternallyConsistent)
        #expect(profile.subscription.effectivePlan == .pro)
        #expect(profile.currentDevice != nil)
    }

    /// The challenge carries no secret; its fields are named, not counted, so adding one is decided here.
    @Test("carries no secret of any kind")
    func challengeIsNotACredential() async throws {
        let challenge = try await service().beginSignIn(with: .google)
        let fields = Mirror(reflecting: challenge).children.compactMap(\.label).sorted()
        #expect(fields == ["authorisationURL", "method", "state"], "the challenge grew a field: \(fields)")
    }

    /// The state proves an answer belongs to this attempt; a development service must not wave any through.
    @Test("refuses a challenge that does not answer the attempt it claims to")
    func mismatchedState() async throws {
        let service = service()
        let real = try await service.beginSignIn(with: .google)

        await #expect(throws: AccountError.self) {
            try await service.completeSignIn(
                SignInChallenge(authorisationURL: real.authorisationURL, state: "somebody else's"))
        }
    }

    @Test("refuses to complete a sign-in that was never begun")
    func completionWithoutAChallenge() async throws {
        let orphan = SignInChallenge(
            authorisationURL: safeURL("https://sign-in.invalid/uttrflow"), state: "x")
        await #expect(throws: AccountError.self) {
            try await service().completeSignIn(orphan)
        }
    }

    /// A challenge is spent once. Replaying it must not mint a second session.
    @Test("spends a challenge, so the same one cannot be used twice")
    func challengeIsSpent() async throws {
        let service = service()
        let challenge = try await service.beginSignIn(with: .apple)
        _ = try await service.completeSignIn(challenge)

        await #expect(throws: AccountError.self) { try await service.completeSignIn(challenge) }
    }

    @Test("re-reads the same account, further into the future")
    func rereading() async throws {
        let service = service()
        let signedIn = try await service.completeSignIn(
            try await service.beginSignIn(with: .google))

        let refreshed = try await service.currentProfile(ifChangedFrom: nil)
        let renewed = try #require(refreshed.updatedProfile)
        #expect(renewed.account == signedIn.account)
        #expect(Fixture.verifier.isAuthentic(renewed.entitlement))
    }

    /// A caller holding the copy this service last handed out is told it is current.
    @Test("answers unchanged for a caller holding the current copy")
    func unchangedForTheCurrentCopy() async throws {
        let service = service()
        let signedIn = try await service.completeSignIn(
            try await service.beginSignIn(with: .google))

        #expect(try await service.currentProfile(ifChangedFrom: signedIn) == .unchanged)
    }

    /// Not ``ProfileRefresh/signedOut``: a missing credential deletes no cached profile in development.
    @Test("says it has no credential when nobody has signed in")
    func noCredentialWhenNobodyHas() async throws {
        #expect(try await service().currentProfile(ifChangedFrom: nil) == .noCredential)
    }

    @Test("signs out, and stops answering afterwards")
    func signingOut() async throws {
        let service = service()
        _ = try await service.completeSignIn(try await service.beginSignIn(with: .google))
        await service.signOut()
        #expect(try await service.currentProfile(ifChangedFrom: nil) == .noCredential)
    }

    @Test("mints whichever plan it was configured with", arguments: Plan.allCases)
    func plans(plan: Plan) async throws {
        let service = service(plan: plan)
        let profile = try await service.completeSignIn(
            try await service.beginSignIn(with: .google))
        #expect(profile.entitlement.plan == plan)
        #expect(profile.subscription.plan == plan)
        // Free does not end; a paid plan always has a date, or the schema would refuse it.
        #expect((profile.subscription.currentPeriodEnd == nil) == (plan == .free))
    }

    /// The app opens this URL exactly as it opens the real one, so the code path is rehearsed.
    @Test("names the provider and the state in a URL the app can open")
    func challengeURL() async throws {
        let challenge = try await service().beginSignIn(with: .gitHub)
        let query = try #require(
            URLComponents(url: challenge.authorisationURL, resolvingAgainstBaseURL: false)?
                .queryItems)

        #expect(query.contains(URLQueryItem(name: "provider", value: "gitHub")))
        #expect(query.contains(URLQueryItem(name: "state", value: challenge.state)))
        // A reserved domain, so a development build cannot reach anybody by accident.
        #expect(challenge.authorisationURL.host()?.hasSuffix(".invalid") == true)
    }

    @Test("gives every attempt its own state value")
    func statesAreUnique() async throws {
        let service = service()
        let first = try await service.beginSignIn(with: .google)
        let second = try await service.beginSignIn(with: .google)
        #expect(first.state != second.state)
    }

    /// The signature check is live in development; an accept-all verifier is how a build ships with none.
    @Test("publishes a verifier that believes what it signs, and only that")
    func matchingVerifier() async throws {
        let service = InMemoryAuthenticationService(now: { Fixture.noon })
        let profile = try await service.completeSignIn(
            try await service.beginSignIn(with: .google))

        #expect(service.verifier.isAuthentic(profile.entitlement))
        #expect(service.verifier.isAuthentic(Fixture.entitlement(expiring: 1)) == false)
    }

    /// Long for a session and short for a subscription, which is what an entitlement is.
    @Test("mints entitlements that outlast a month of aeroplanes by default")
    func defaultLifetime() async throws {
        let service = InMemoryAuthenticationService(now: { Fixture.noon })
        let profile = try await service.completeSignIn(
            try await service.beginSignIn(with: .google))
        #expect(profile.entitlement.isCurrent(at: Fixture.noon.addingTimeInterval(29 * 86_400)))
        #expect(InMemoryAuthenticationService.defaultLifetime == 30 * 24 * 60 * 60)
    }

    /// Built with no arguments as the development app does: a fresh key, the real clock, and dated from now.
    @Test("needs no arguments, and dates its entitlements from now")
    func allDefaults() async throws {
        let before = Date()
        let service = InMemoryAuthenticationService()
        let profile = try await service.completeSignIn(
            try await service.beginSignIn(with: .google))

        #expect(
            profile.entitlement.expiresAt
                >= before.addingTimeInterval(InMemoryAuthenticationService.defaultLifetime))
        #expect(profile.entitlement.isCurrent(at: Date()))
        #expect(service.verifier.isAuthentic(profile.entitlement))
    }

    /// `safeURL` exists because the package forbids a force unwrap and `URL(string:)` is failable.
    @Test("builds a URL from a literal without a force unwrap, and copes with a bad one")
    func safeURLs() {
        #expect(safeURL("https://sign-in.invalid/uttrflow").host() == "sign-in.invalid")
        #expect(safeURL("").isFileURL)
    }
}
