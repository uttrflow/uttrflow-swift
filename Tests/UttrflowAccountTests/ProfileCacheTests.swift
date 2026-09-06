// Tests for UserDefaultsProfileCache and SystemDefaultsStorage.

import Foundation
import UttrflowCore
import Testing
import UttrflowTestSupport

@testable import UttrflowAccount

/// The cache that keeps the signed profile between launches and refuses what it cannot verify.
@Suite("The profile, kept between launches")
struct ProfileCacheTests {
    /// A cache over `storage` that checks signatures with the test backend's key.
    private func cache(_ storage: MemoryStorage) -> UserDefaultsProfileCache {
        UserDefaultsProfileCache(storage: storage, verifier: Fixture.verifier)
    }

    /// Rule 2: what the first launch writes is what every later launch reads, with nothing asked of anybody.
    @Test("gives back exactly what was signed in")
    func roundTrip() throws {
        let storage = MemoryStorage()
        let profile = Fixture.profile(for: Fixture.entitlement(expiring: 86_400))
        try cache(storage).save(profile)

        // A second cache over the same bytes, because the launch that reads is never the one that wrote.
        #expect(cache(storage).load() == profile)
    }

    @Test("has no session before anybody has signed in")
    func emptyToBeginWith() {
        #expect(cache(MemoryStorage()).load() == nil)
    }

    /// Corrupt data degrades to signed out; a mangled file must not take the app down.
    @Test("degrades to signed out rather than crashing on nonsense")
    func corruptDataIsNoSession() {
        for bytes in [Data(), Data("{".utf8), Data("null".utf8), Data([0xFF, 0xFE, 0x00])] {
            let storage = MemoryStorage([UserDefaultsProfileCache.defaultKey: bytes])
            #expect(cache(storage).load() == nil, "\(bytes) was believed")
        }
    }

    /// Readable JSON of the right shape, signed by the wrong person: decoding is not believing.
    @Test("degrades to signed out when the session was signed by somebody else")
    func forgedDataIsNoSession() throws {
        let storage = MemoryStorage()
        let forgery = Fixture.entitlement(expiring: 86_400, signedBy: Fixture.impostor)
        try UserDefaultsProfileCache(storage: storage, verifier: CredulousVerifier())
            .save(Fixture.profile(for: forgery))

        #expect(storage.data(forKey: UserDefaultsProfileCache.defaultKey) != nil)
        #expect(cache(storage).load() == nil)
    }

    /// Refused at the door, so the failure surfaces in the sign-in that caused it, not as a later sign-out.
    @Test("refuses to keep a session it cannot verify")
    func saveRejectsAForgery() {
        let storage = MemoryStorage()
        let forgery = Fixture.entitlement(expiring: 86_400, signedBy: Fixture.impostor)

        #expect(throws: AccountError.sessionMalformed) {
            try cache(storage).save(Fixture.profile(for: forgery))
        }
        #expect(storage.keys.isEmpty, "a session that could not be verified was written anyway")
    }

    /// An aged-out entitlement is still a session; what it permits is ``EntitlementGate``'s call, not this.
    @Test("returns an expired session rather than pretending there is none")
    func expiredSessionsSurviveTheStore() throws {
        let storage = MemoryStorage()
        let expired = Fixture.profile(for: Fixture.entitlement(expiring: -365 * 86_400))
        try cache(storage).save(expired)
        #expect(cache(storage).load() == expired)
    }

    /// Rule 4: signing out removes the session only; the other keys stand in for the user's own data.
    @Test("signing out removes the session and leaves every other thing on the Mac alone")
    func signingOutKeepsLocalData() throws {
        let neighbours = [
            "com.uttrflow.settings.v1": Data("settings".utf8),
            "com.uttrflow.dictionary.v1": Data("dictionary".utf8),
            "com.uttrflow.history.v1": Data("history".utf8),
        ]
        let storage = MemoryStorage(neighbours)
        let cache = cache(storage)
        try cache.save(Fixture.profile(for: Fixture.entitlement(expiring: 86_400)))

        cache.clear()

        #expect(cache.load() == nil)
        for (key, value) in neighbours {
            #expect(storage.data(forKey: key) == value, "signing out destroyed \(key)")
        }
    }

    @Test("writes under a versioned key, so a future shape can sit beside this one")
    func versionedKey() throws {
        let storage = MemoryStorage()
        try cache(storage).save(Fixture.profile(for: Fixture.entitlement(expiring: 86_400)))
        #expect(storage.keys == [UserDefaultsProfileCache.defaultKey])
        #expect(UserDefaultsProfileCache.defaultKey.hasSuffix(".v1"))
    }

    /// The default verifier is the release one, so a store built without arguments fails closed too.
    @Test("checks signatures by default")
    func defaultsToTheReleaseVerifier() {
        let storage = MemoryStorage()
        let cache = UserDefaultsProfileCache(storage: storage)
        #expect(throws: AccountError.sessionMalformed) {
            try cache.save(Fixture.profile(for: Fixture.entitlement(expiring: 86_400)))
        }
    }
}

/// The storage that backs the cache with a real `UserDefaults` domain.
@Suite("The app's own defaults domain")
struct SystemDefaultsStorageTests {
    @Test("keeps a value, gives it back, and removes it")
    func roundTripThroughUserDefaults() {
        withTemporaryDefaultsSuite { suite in
            let storage = SystemDefaultsStorage(suiteName: suite.name)

            let key = "session"
            #expect(storage.data(forKey: key) == nil)

            storage.set(Data("kept".utf8), forKey: key)
            #expect(storage.data(forKey: key) == Data("kept".utf8))

            storage.set(nil, forKey: key)
            #expect(storage.data(forKey: key) == nil)
        }
    }

    /// Only absence is asserted: writing to the standard domain writes into the runner's own preferences.
    @Test("reads the standard domain when no suite is named")
    func standardDomain() {
        #expect(SystemDefaultsStorage().data(forKey: "com.uttrflow.absent.\(UUID().uuidString)") == nil)
    }
}
