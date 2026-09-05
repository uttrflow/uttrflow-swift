import Foundation
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowAccount

/// A backend that answers with whatever the test put in it.
private final class ScriptedService: AuthenticationService {
    private let answer: Result<ProfileRefresh, AccountError>
    private let asked = Mutex<[Profile?]>([])

    init(_ answer: Result<ProfileRefresh, AccountError>) {
        self.answer = answer
    }

    /// What each call was told the cache holds, so a test can check the validator travels.
    var cachedCopiesSeen: [Profile?] { asked.withLock { $0 } }

    func beginSignIn(with provider: SignInProvider) async throws(AccountError) -> SignInChallenge {
        throw .serverUnreachable
    }

    func completeSignIn(_ challenge: SignInChallenge) async throws(AccountError) -> Profile {
        throw .serverUnreachable
    }

    func currentProfile(ifChangedFrom cached: Profile?) async throws(AccountError) -> ProfileRefresh {
        asked.withLock { $0.append(cached) }
        switch answer {
        case .success(let refresh): return refresh
        case .failure(let failure): throw failure
        }
    }

    /// No pictures here: these tests are about what a refresh decides, and a face
    /// decides nothing.
    func avatar(at path: String) async -> Data? { nil }

    func signOut() async {}
}

@Suite("Re-reading the account at launch")
struct AccountRefreshTests {
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

    /// Somebody signed this machine out from another one. Carrying that out locally is the
    /// whole point of the device list being real rather than decorative.
    @Test("clears the copy when the server says the session is over")
    func signedOutElsewhere() async {
        let cache = Fixture.cacheHolding(profile: current)

        let outcome = await AccountRefresh(
            service: ScriptedService(.success(.signedOut)), profiles: cache
        ).run()

        #expect(outcome == .signedOut)
        #expect(cache.load() == nil)
    }

    /// The offline promise, as one test: a Mac that cannot reach the server keeps working
    /// exactly as it did.
    @Test("changes nothing at all when the server cannot be reached", arguments: AccountError.everyCase)
    func failuresChangeNothing(failure: AccountError) async {
        let cache = Fixture.cacheHolding(profile: current)

        let outcome = await AccountRefresh(
            service: ScriptedService(.failure(failure)), profiles: cache
        ).run()

        #expect(outcome == .unavailable)
        #expect(cache.load() == current)
    }

    /// A profile that fails the signature check is dropped rather than cached. The one
    /// already on disk was believed once and keeps working, which is the safer of the two
    /// wrong answers.
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

    /// The regression this suite exists for. A Mac whose Keychain has lost the refresh
    /// token — an ad-hoc-signed build, where `SecItemAdd` refuses the data protection
    /// keychain outright, or a signing identity that changed — still holds a profile the
    /// backend signed, and the backend has not disowned it. Deleting it here is what made
    /// a real, completed Google sign-in show as "Not signed in" on the next launch, and it
    /// is the exact failure the profile was kept out of the Keychain to prevent.
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
