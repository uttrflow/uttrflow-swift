// Working without an account: the local account and where it is kept.
public import struct Foundation.Date

private import Synchronization

/// The person at this Mac with no account: a name macOS knows them by and a moment, never a subscription.
public struct LocalAccount: Sendable, Equatable, Codable {
    /// What macOS calls the person at this Mac, or `nil` when it would not say; never invented.
    public let name: String?

    /// When this Mac was chosen over an account, so the Account page can say how long.
    public let since: Date

    /// Normalises an empty or blank name to `nil`, so no page has to.
    public init(name: String?, since: Date) {
        // An empty name and no name mean the same thing to every page, so it is normalised once here.
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.since = since
    }
}

/// Remembers the choice to work without an account; a statement, not a credential, so not the Keychain.
public protocol LocalAccountStore: Sendable {
    /// The local account, or `nil` when nobody chose one; never throws, and a corrupt one reads as none.
    func load() -> LocalAccount?

    /// Records that this Mac is being used without an account.
    func save(_ account: LocalAccount)

    /// Forgets it, at the moment somebody signs in for real, so the two are never both present.
    func clear()
}

/// The local account, kept in `UserDefaults` as one small JSON document.
public struct UserDefaultsLocalAccountStore: LocalAccountStore {
    /// Versioned, so a future shape can be introduced beside this one rather than on top of it.
    public static let defaultKey = "com.uttrflow.local-account.v1"

    /// The defaults domain.
    private let storage: any SessionStorage
    /// The key the document is under.
    private let key: String

    /// Uses the app's own defaults unless told otherwise.
    public init(storage: any SessionStorage = SystemDefaultsStorage(), key: String = defaultKey) {
        self.storage = storage
        self.key = key
    }

    /// The document under `key`, or `nil`.
    public func load() -> LocalAccount? {
        storage.decoded(LocalAccount.self, forKey: key)
    }

    /// Writes the document under `key`.
    public func save(_ account: LocalAccount) {
        storage.set(encoding: account, forKey: key)
    }

    /// Removes the document.
    public func clear() {
        storage.set(nil, forKey: key)
    }
}

/// A store that forgets when the process ends, kept in the module so it cannot drift from the protocol.
public final class InMemoryLocalAccountStore: LocalAccountStore {
    /// The account, behind a lock.
    private let account: Mutex<LocalAccount?>

    /// Starts holding `account`.
    public init(_ account: LocalAccount? = nil) {
        self.account = Mutex(account)
    }

    /// The account held.
    public func load() -> LocalAccount? { account.withLock { $0 } }

    /// Replaces the account held.
    public func save(_ account: LocalAccount) { self.account.withLock { $0 = account } }

    /// Drops the account held.
    public func clear() { account.withLock { $0 = nil } }
}
