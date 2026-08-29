public import UttrflowCore
private import Synchronization

/// Where the refresh token lives.
///
/// A refresh token *is* a credential: ninety days of being this person, exchangeable for
/// access to their account from any machine that has a copy. That is the whole difference
/// between it and the profile beside it, and the reason the two are stored differently.
/// A cached ``Profile`` goes in `UserDefaults`, because a copy of it cannot be exchanged
/// for anything; this goes in the Keychain, because a copy of it can.
///
/// The comparison worth keeping in mind is a shipping competitor that puts exactly this
/// value — access token, refresh token and the user's email — in a plain JSON file in
/// Application Support, world-readable. Every process running as any user on that Mac can
/// lift a ninety-day session out of it. The Keychain costs one protocol and one small
/// file to avoid that.
public protocol TokenStore: Sendable {
    /// The refresh token on this Mac, or `nil` when nobody is signed in.
    func refreshToken() -> String?

    /// Replaces it. Called on every rotation, which is every hour of active use.
    ///
    /// - Throws: ``AccountError/sessionCouldNotBeKept`` when the token could not be
    ///   written. It throws rather than returning quietly because a caller that treats a
    ///   failed write as a successful sign-in shows somebody their account and then signs
    ///   them out at the next launch, with nothing on screen to connect the two.
    func store(_ refreshToken: String) throws(AccountError)

    /// Signs out. Removes the credential and nothing else — the profile, the history and
    /// the dictionary are not credentials and are not this type's to delete.
    func clear()
}

/// A token store that forgets everything when the process ends.
///
/// Ships in the module rather than in the tests, for the same two reasons
/// ``InMemoryAuthenticationService`` does: a development build with no Keychain entry has
/// to run, and a fake that lives beside the real protocol cannot drift away from it.
public final class InMemoryTokenStore: TokenStore {
    private let token: Mutex<String?>

    public init(refreshToken: String? = nil) {
        token = Mutex(refreshToken)
    }

    public func refreshToken() -> String? { token.withLock { $0 } }

    public func store(_ refreshToken: String) { token.withLock { $0 = refreshToken } }

    public func clear() { token.withLock { $0 = nil } }
}
