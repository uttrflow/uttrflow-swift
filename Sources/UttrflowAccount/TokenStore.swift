// Where the refresh token lives, and the store that forgets.
public import UttrflowCore
private import Synchronization

/// Where the refresh token lives: the Keychain, because a copy of it is ninety days of being this person.
public protocol TokenStore: Sendable {
    /// The refresh token on this Mac, or `nil` when nobody is signed in.
    func refreshToken() -> String?

    /// Replaces it on every rotation; a write that fails throws ``AccountError/sessionCouldNotBeKept``.
    func store(_ refreshToken: String) throws(AccountError)

    /// Signs out, removing the credential and nothing else the user owns.
    func clear()
}

/// A token store that forgets when the process ends, in the module so it cannot drift from the protocol.
public final class InMemoryTokenStore: TokenStore {
    /// The token, behind a lock.
    private let token: Mutex<String?>

    /// Starts holding `refreshToken`.
    public init(refreshToken: String? = nil) {
        token = Mutex(refreshToken)
    }

    /// The token held.
    public func refreshToken() -> String? { token.withLock { $0 } }

    /// Replaces the token held.
    public func store(_ refreshToken: String) { token.withLock { $0 = refreshToken } }

    /// Drops the token held.
    public func clear() { token.withLock { $0 = nil } }
}
