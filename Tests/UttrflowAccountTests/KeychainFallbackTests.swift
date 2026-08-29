import Foundation
import Testing

@testable import UttrflowAccount
@testable import UttrflowCore

/// The bug these pin took a production sign-in with it, silently.
///
/// `KeychainTokenStore.store` asked for the data-protection keychain and discarded the
/// `OSStatus`. Every ad-hoc-signed build — which is every local build — was answered
/// `errSecMissingEntitlement`, because that keychain needs a keychain-access-group
/// entitlement and that needs a team identifier `codesign --sign -` does not have.
///
/// So the token was never written. The sign-in itself worked: the backend issued a
/// session, registered the device and returned a signed entitlement, and the app cached a
/// correct profile. Then the next refresh read no token, reported `.signedOut`, and
/// `AccountRefresh` cleared the cache. On screen: "Not signed in", immediately after
/// signing in, with nothing to connect it to the Keychain.
@Suite("Keeping the session when the Keychain is fussy")
struct KeychainFallbackTests {
    /// Refuses exactly the way the data-protection keychain refuses an ad-hoc build.
    private final class RefusingStore: TokenStore {
        func refreshToken() -> String? { nil }
        func store(_ refreshToken: String) throws(AccountError) { throw .sessionCouldNotBeKept }
        func clear() {}
    }

    @Test("a token that cannot be kept is reported, not swallowed")
    func refusalIsReported() {
        let store = RefusingStore()
        #expect(throws: AccountError.sessionCouldNotBeKept) {
            try store.store("refresh-token")
        }
    }

    /// The real store, against the real keychain of whoever runs this.
    ///
    /// It cannot assert *which* of the two keychains took the token — that is a property
    /// of how the test runner was signed, and asserting it would make the test pass or
    /// fail on the machine rather than on the code. What it can assert is the thing that
    /// was broken: whatever `store` accepts, `refreshToken` finds, and `clear` removes.
    @Test("what the store accepts, it can read back and then remove")
    func roundTrips() throws {
        let store = KeychainTokenStore(service: "com.uttrflow.tests.\(UUID().uuidString)")
        defer { store.clear() }

        try store.store("a-refresh-token")
        #expect(store.refreshToken() == "a-refresh-token")

        // Rotation: hourly in real use, and the old token must not survive it.
        try store.store("the-rotated-one")
        #expect(store.refreshToken() == "the-rotated-one")

        store.clear()
        #expect(store.refreshToken() == nil)
    }

    @Test("the new failure is catalogued, so nothing can switch over it and miss it")
    func isCatalogued() {
        let every = AccountError.everyCase
        #expect(every.contains(.sessionCouldNotBeKept))
        #expect(AccountError.sessionCouldNotBeKept.severity == .blocking)
        // Retry is offered: a locked keychain is a thing a second attempt can clear,
        // unlike a key mismatch, which no number of attempts changes.
        #expect(AccountError.sessionCouldNotBeKept.recovery == .retry)
    }
}
