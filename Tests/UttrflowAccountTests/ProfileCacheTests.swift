import Foundation
import UttrflowCore
import Testing
import UttrflowTestSupport

@testable import UttrflowAccount

@Suite("The profile, kept between launches")
struct ProfileCacheTests {
    private func cache(_ storage: MemoryStorage) -> UserDefaultsProfileCache {
        UserDefaultsProfileCache(storage: storage, verifier: Fixture.verifier)
    }

    /// Rule 2, in one test: what the first launch wrote is what every launch after it
    /// reads, with nothing asked of anybody in between.
    @Test("gives back exactly what was signed in")
    func roundTrip() throws {
        let storage = MemoryStorage()
        let profile = Fixture.profile(for: Fixture.entitlement(expiring: 86_400))
        try cache(storage).save(profile)

        // A second cache over the same bytes, because the launch that reads is never
        // the one that wrote.
        #expect(cache(storage).load() == profile)
    }

    @Test("has no session before anybody has signed in")
    func emptyToBeginWith() {
        #expect(cache(MemoryStorage()).load() == nil)
    }

    /// Corrupt data degrades to signed out. Losing the session is recoverable in
    /// seconds; losing the app to a file somebody mangled is not.
    @Test("degrades to signed out rather than crashing on nonsense")
    func corruptDataIsNoSession() {
        for bytes in [Data(), Data("{".utf8), Data("null".utf8), Data([0xFF, 0xFE, 0x00])] {
            let storage = MemoryStorage([UserDefaultsProfileCache.defaultKey: bytes])
            #expect(cache(storage).load() == nil, "\(bytes) was believed")
        }
    }

    /// Readable JSON of the right shape, signed by the wrong person. Decoding is not
    /// believing.
    @Test("degrades to signed out when the session was signed by somebody else")
    func forgedDataIsNoSession() throws {
        let storage = MemoryStorage()
        let forgery = Fixture.entitlement(expiring: 86_400, signedBy: Fixture.impostor)
        try UserDefaultsProfileCache(storage: storage, verifier: CredulousVerifier())
            .save(Fixture.profile(for: forgery))

        #expect(storage.data(forKey: UserDefaultsProfileCache.defaultKey) != nil)
        #expect(cache(storage).load() == nil)
    }

    /// Refused at the door, so the failure surfaces during the sign-in that caused it
    /// rather than as a mysterious sign-out on the next launch.
    @Test("refuses to keep a session it cannot verify")
    func saveRejectsAForgery() {
        let storage = MemoryStorage()
        let forgery = Fixture.entitlement(expiring: 86_400, signedBy: Fixture.impostor)

        #expect(throws: AccountError.sessionMalformed) {
            try cache(storage).save(Fixture.profile(for: forgery))
        }
        #expect(storage.keys.isEmpty, "a session that could not be verified was written anyway")
    }

    /// An entitlement that has aged out is still a session and is still returned.
    /// Deciding what it permits belongs to ``EntitlementGate``, and a store that took
    /// the decision by returning `nil` would lock out exactly the user this module
    /// exists to protect.
    @Test("returns an expired session rather than pretending there is none")
    func expiredSessionsSurviveTheStore() throws {
        let storage = MemoryStorage()
        let expired = Fixture.profile(for: Fixture.entitlement(expiring: -365 * 86_400))
        try cache(storage).save(expired)
        #expect(cache(storage).load() == expired)
    }

    /// Rule 4. Signing out removes the session and nothing else — the history, the
    /// dictionary and the settings are the user's own and are not this store's to
    /// touch. The other keys stand in for them here because they share the domain.
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

    /// The default verifier is the release one, which believes nothing until a real key
    /// is compiled in. A store built without arguments must therefore fail closed too,
    /// rather than quietly skipping the check.
    @Test("checks signatures by default")
    func defaultsToTheReleaseVerifier() {
        let storage = MemoryStorage()
        let cache = UserDefaultsProfileCache(storage: storage)
        #expect(throws: AccountError.sessionMalformed) {
            try cache.save(Fixture.profile(for: Fixture.entitlement(expiring: 86_400)))
        }
    }
}

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

    /// Without a suite name it reads the standard domain, which the app itself uses.
    /// Only the absence of a value is asserted: writing there would be writing into the
    /// preferences of whoever is running the tests.
    @Test("reads the standard domain when no suite is named")
    func standardDomain() {
        #expect(SystemDefaultsStorage().data(forKey: "com.uttrflow.absent.\(UUID().uuidString)") == nil)
    }
}
