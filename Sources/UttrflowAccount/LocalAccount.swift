public import struct Foundation.Data
public import struct Foundation.Date

public import class Foundation.JSONDecoder
public import class Foundation.JSONEncoder

private import Synchronization

/// Somebody using Uttrflow as themselves on this Mac, without an Uttrflow account.
///
/// The product asks for an account once, over the network, and then never again. That one
/// step is also the only one that can fail for reasons the person cannot fix: a captive
/// portal, a corporate proxy, a provider having an outage, a Mac with no browser it is
/// allowed to open. Before this existed the answer to all of those was a sign-in page with
/// nowhere to go, on a product whose entire claim is that it works on your own machine.
///
/// So there is a second way in, and it is deliberately the smallest one that can be true:
/// **the name macOS already knows this person by, and the moment they chose it.** Nothing
/// is invented, nothing is fetched, and nothing here is a claim about a subscription —
/// which is why it is a separate type from ``Entitlement`` rather than a locally minted
/// one. An entitlement is a signed statement from the backend about what somebody has paid
/// for. This is a statement by the user about who is sitting at the Mac, and the two must
/// never be confusable: a local account that could be decoded as an entitlement would be
/// a way to mint a subscription with a text editor.
///
/// It is not a lesser tier and it is not a trial. Dictation is on-device, so there is
/// nothing here for the server to permit; what an account buys is the things that need
/// one — carrying a dictionary between Macs, and a subscription to bill. Signing in later
/// replaces this, and ``LocalAccountStore/clear()`` is called at that moment so the two
/// can never both be present and disagree about who is here.
public struct LocalAccount: Sendable, Equatable, Codable {
    /// What macOS calls the person at this Mac, or `nil` when it would not say.
    ///
    /// Optional because a name is not required for any of this to work, and inventing one
    /// would be worse than having none: the pages that show it already know how to end a
    /// sentence early rather than greet a stranger.
    public let name: String?

    /// When this Mac was chosen over an account. Recorded so the Account page can say
    /// how long this has been the arrangement rather than presenting it as something that
    /// happened to the user.
    public let since: Date

    public init(name: String?, since: Date) {
        // An empty name and no name mean the same thing to every page that draws this,
        // and normalising here is what keeps them from each having to know that.
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.since = since
    }
}

/// Where the choice to work without an account is remembered.
///
/// `UserDefaults` rather than the Keychain, for the same reason ``ProfileCache`` is: this
/// is a statement, not a credential. There is nothing in it to steal — somebody reading
/// your defaults already knows your Mac's owner's name, because macOS told them — and
/// nothing that can be exchanged for anything at any server.
///
/// Separate from ``ProfileCache`` rather than a case inside it, because the two answer
/// different questions and only one of them is signed. Folding a local account into the
/// profile would mean ``EntitlementGate`` reading a subscription out of a value the
/// backend never signed, which is precisely the door that module exists to keep shut.
public protocol LocalAccountStore: Sendable {
    /// The local account on this Mac, or `nil` when nobody chose one.
    ///
    /// Never throws and never traps. Absent, corrupt, or written by a build that knew
    /// different fields all mean the same thing: no local account, and the app still
    /// opens on the sign-in page it would have shown anyway.
    func load() -> LocalAccount?

    /// Records that this Mac is being used without an account.
    func save(_ account: LocalAccount)

    /// Forgets it. Called when somebody signs in for real, so that an account and a local
    /// account are never both present.
    func clear()
}

/// The local account, kept in `UserDefaults` as one small JSON document.
public struct UserDefaultsLocalAccountStore: LocalAccountStore {
    /// Versioned for the same reason every other key here is: a future shape can be
    /// introduced beside this one rather than on top of it.
    public static let defaultKey = "com.uttrflow.local-account.v1"

    private let storage: any SessionStorage
    private let key: String

    public init(storage: any SessionStorage = SystemDefaultsStorage(), key: String = defaultKey) {
        self.storage = storage
        self.key = key
    }

    public func load() -> LocalAccount? {
        guard let data = storage.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LocalAccount.self, from: data)
    }

    public func save(_ account: LocalAccount) {
        // A value of one optional string and one date cannot fail to encode, so there is
        // no second failure to report and no caller left holding one it could not act on.
        storage.set(try? JSONEncoder().encode(account), forKey: key)
    }

    public func clear() {
        storage.set(nil, forKey: key)
    }
}

/// A local account that forgets itself when the process ends.
///
/// Ships in the module rather than in the tests, for the reason ``InMemoryTokenStore``
/// does: a fake that lives beside the real protocol cannot drift away from it.
public final class InMemoryLocalAccountStore: LocalAccountStore {
    private let account: Mutex<LocalAccount?>

    public init(_ account: LocalAccount? = nil) {
        self.account = Mutex(account)
    }

    public func load() -> LocalAccount? { account.withLock { $0 } }

    public func save(_ account: LocalAccount) { self.account.withLock { $0 = account } }

    public func clear() { account.withLock { $0 = nil } }
}
