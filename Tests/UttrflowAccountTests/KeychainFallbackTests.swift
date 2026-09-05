import Foundation
import Testing

@testable import UttrflowAccount
@testable import UttrflowCore

/// A store that cannot keep the token says so, never silently; see Docs/account-tests-keychain-adhoc.md.
@Suite("Keeping the session when the Keychain is fussy")
struct KeychainFallbackTests {
    /// Refuses exactly the way the data-protection keychain refuses an ad-hoc build.
    private final class RefusingStore: TokenStore {
        /// Never holds one.
        func refreshToken() -> String? { nil }
        /// Refuses, as the data-protection keychain refuses an ad-hoc build.
        func store(_ refreshToken: String) throws(AccountError) { throw .sessionCouldNotBeKept }
        /// Nothing to clear.
        func clear() {}
    }

    @Test("a token that cannot be kept is reported, not swallowed")
    func refusalIsReported() {
        let store = RefusingStore()
        #expect(throws: AccountError.sessionCouldNotBeKept) {
            try store.store("refresh-token")
        }
    }

    /// The real store against the runner's keychain; which one takes the token depends on the signature.
    @Test("what the store accepts, it can read back and then remove")
    func roundTrips() throws {
        let store = KeychainTokenStore(service: "com.uttrflow.tests.\(UUID().uuidString)")
        defer { store.clear() }

        try store.store("a-refresh-token")
        #expect(store.refreshToken() == "a-refresh-token")

        // Rotation: hourly in real use, and the replaced token must not survive it.
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
        // Retry is offered: a locked keychain is a thing a second attempt can clear, unlike a key mismatch.
        #expect(AccountError.sessionCouldNotBeKept.recovery == .retry)
    }
}
