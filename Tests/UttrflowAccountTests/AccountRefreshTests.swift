// Tests for AccountRefresh: what the launch re-read does to the cached profile for each answer.

import Foundation
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowAccount

/// A backend that answers with whatever the test put in it.
private final class ScriptedService: AuthenticationService {
    /// What every `currentProfile` call answers.
    private let answer: Result<ProfileRefresh, AccountError>
    /// The cached copy each call is told about.
    private let asked = Mutex<[Profile?]>([])

    /// A service that always answers `answer`.
    init(_ answer: Result<ProfileRefresh, AccountError>) {
        self.answer = answer
    }

    /// What each call was told the cache holds, so a test can check the validator travels.
    var cachedCopiesSeen: [Profile?] { asked.withLock { $0 } }

    /// Not part of a refresh; always throws.
    func beginSignIn(with provider: SignInProvider) async throws(AccountError) -> SignInChallenge {
        throw .serverUnreachable
    }

    /// Not part of a refresh; always throws.
    func completeSignIn(_ challenge: SignInChallenge) async throws(AccountError) -> Profile {
        throw .serverUnreachable
    }

    /// Records `cached`, then returns or throws `answer`.
    func currentProfile(ifChangedFrom cached: Profile?) async throws(AccountError) -> ProfileRefresh {
        asked.withLock { $0.append(cached) }
        switch answer {
        case .success(let refresh): return refresh
        case .failure(let failure): throw failure
        }
    }

    /// No pictures: a refresh decides nothing from a face.
    func avatar(at path: String) async -> Data? { nil }

    /// Nothing to forget.
    func signOut() async {}
}

/// Each ``ProfileRefresh`` answer, and every failure, against a cache holding a current profile.
@Suite("Re-reading the account at launch")
struct AccountRefreshTests {
    /// The profile the cache starts with.
    private let current = Fixture.profile(for: Fixture.entitlement(expiring: 86_400))

    @Test("hands the server the copy it already has, so an unchanged one costs nothing")
    func sendsTheCachedCopy() async {
        let service = ScriptedService(.success(.unchanged))
        let cache = Fixture.cacheHolding(profile: current)

        #expect(await AccountRefresh(service: service, profiles: cache).run() == .unchanged)
        #expect(service.cachedCopiesSeen == [current])
        #expect(cache.load() == current, "an unchanged answer rewrote the cache")
    }

    @Test("replaces the whole copy when a newer one arrives")
    func replacesTheCopy() async throws {
        let newer = Fixture.profile(
            for: Fixture.entitlement(expiring: 30 * 86_400), validator: "\"newer\"")
        let cache = Fixture.cacheHolding(profile: current)

        let outcome = await AccountRefresh(
            service: ScriptedService(.success(.updated(newer))), profiles: cache
        ).run()

        #expect(outcome == .updated)
        #expect(cache.load() == newer)
    }

    /// A sign-out from another machine is carried out locally, which is what makes the device list real.
    @Test("clears the copy when the server says the session is over")
    func signedOutElsewhere() async {
        let cache = Fixture.cacheHolding(profile: current)

        let outcome = await AccountRefresh(
            service: ScriptedService(.success(.signedOut)), profiles: cache
        ).run()

        #expect(outcome == .signedOut)
        #expect(cache.load() == nil)
    }

    /// The offline promise: a Mac that cannot reach the server keeps working exactly as before.
    @Test("changes nothing at all when the server cannot be reached", arguments: AccountError.everyCase)
    func failuresChangeNothing(failure: AccountError) async {
        let cache = Fixture.cacheHolding(profile: current)

        let outcome = await AccountRefresh(
            service: ScriptedService(.failure(failure)), profiles: cache
        ).run()

        #expect(outcome == .unavailable)
        #expect(cache.load() == current)
    }

    /// A profile failing the signature check is dropped, and the one already on disk keeps working.
    @Test("keeps the copy it has rather than caching one it cannot believe")
    func anUnbelievableUpdateIsDropped() async {
        let forged = Fixture.profile(
            for: Fixture.entitlement(expiring: 86_400, signedBy: Fixture.impostor))
        let cache = Fixture.cacheHolding(profile: current)

        let outcome = await AccountRefresh(
            service: ScriptedService(.success(.updated(forged))), profiles: cache
        ).run()

        #expect(outcome == .unavailable)
        #expect(cache.load() == current)
    }

    /// No refresh token still leaves a profile the server honours; see Docs/account-tests-keychain-adhoc.md.
    @Test("keeps the copy when this Mac has no credential left to renew it with")
    func noCredentialIsNotASignOut() async {
        let cache = Fixture.cacheHolding(profile: current)

        let outcome = await AccountRefresh(
            service: ScriptedService(.success(.noCredential)), profiles: cache
        ).run()

        #expect(outcome == .noCredential)
        #expect(cache.load() == current, "a missing credential deleted a profile the server still honours")
    }

    @Test("asks for everything when this Mac has nothing cached")
    func nothingCached() async {
        let service = ScriptedService(.success(.signedOut))
        _ = await AccountRefresh(service: service, profiles: Fixture.cacheHolding(nil)).run()
        #expect(service.cachedCopiesSeen == [nil])
    }
}
