public import UttrflowCore
public import struct Foundation.Data

public import class Foundation.JSONDecoder
public import class Foundation.JSONEncoder
public import class Foundation.UserDefaults

/// The server's answer about this account, kept between launches.
///
/// This is what makes the second launch work on a plane. The backend owns the truth; this
/// holds the most recent copy of it, and the copy is replaced whole rather than edited —
/// there is no operation here for changing one field, deliberately, because a client that
/// could change a field would be a second place the truth lives.
///
/// It is not the Keychain, and that is a decision rather than an oversight: a profile is a
/// *statement*, not a credential. A copy of it cannot be exchanged for anything, and all
/// it discloses to somebody already reading your defaults is which plan you are on. The
/// credential that does need protecting — the refresh token — lives in ``TokenStore``,
/// which is the Keychain. Putting this there too would buy nothing and cost a session that
/// disappears when the signing identity changes, which on a product whose promise is that
/// the second launch needs no network is the expensive failure.
public protocol ProfileCache: Sendable {
    /// The profile on this Mac, or `nil` when there is none worth believing.
    ///
    /// Never throws and never traps. Absent, truncated, corrupt, written by a build that
    /// knew different fields, or signed by somebody who is not the backend — every one
    /// of them means the same thing to a user, which is that they are signed out and
    /// the app still opens.
    ///
    /// Expiry is not considered here. An entitlement that has aged out is still a
    /// session and is still returned; deciding what an aged-out one permits is
    /// ``EntitlementGate``'s job, and it is the decision this whole module exists to get
    /// right.
    func load() -> Profile?

    /// Keeps `entitlement` for every launch after this one.
    ///
    /// - Throws: ``AccountError/sessionMalformed`` when the signature does not check
    ///   out. Refused at the door rather than kept and disbelieved later, so the failure
    ///   surfaces during the sign-in that caused it instead of as a mysterious sign-out
    ///   on the next launch.
    func save(_ profile: Profile) throws(AccountError)

    /// Signs out.
    ///
    /// Removes the profile and nothing else. History, dictionary and settings are the
    /// user's own and stay on the Mac — signing out of an account is not a reason to
    /// delete somebody's words, and a sign-out that wiped them would be unforgivable
    /// the one time it was accidental.
    func clear()
}

/// One blob of bytes under one name, and back again.
///
/// The whole of `UserDefaults` reduced to the two calls the session store makes.
/// Injecting this rather than a `UserDefaults` instance means the store's real
/// behaviour is tested without a defaults domain or anything that outlives the test.
///
/// A near-twin of `KeyValueStore` in `UttrflowSettings`, which is the same two calls for
/// the same reason. They are separate only because this module cannot import that one;
/// the honest home for the protocol is ``UttrflowCore``.
public protocol SessionStorage: Sendable {
    func data(forKey key: String) -> Data?

    /// Stores `data`, or removes the value when it is `nil`.
    func set(_ data: Data?, forKey key: String)
}

/// The profile, kept in `UserDefaults` as one JSON document with a signature inside it.
public struct UserDefaultsProfileCache: ProfileCache {
    /// Versioned so that a future shape too different to be read field by field can be
    /// introduced beside this one rather than on top of it.
    public static let defaultKey = "com.uttrflow.profile.v1"

    private let storage: any SessionStorage
    private let verifier: any EntitlementVerifying
    private let key: String

    public init(
        storage: any SessionStorage = SystemDefaultsStorage(),
        verifier: any EntitlementVerifying = Ed25519EntitlementVerifier.release,
        key: String = defaultKey
    ) {
        self.storage = storage
        self.verifier = verifier
        self.key = key
    }

    public func load() -> Profile? {
        guard let data = storage.data(forKey: key),
            let profile = try? JSONDecoder().decode(Profile.self, from: data),
            isBelievable(profile)
        else { return nil }
        return profile
    }

    public func save(_ profile: Profile) throws(AccountError) {
        guard isBelievable(profile) else { throw .sessionMalformed }
        // Encoding a value of strings, enumerations and dates cannot fail, so there is no
        // second failure to report and no caller left holding one it could do nothing
        // about.
        storage.set(try? JSONEncoder().encode(profile), forKey: key)
    }

    /// Two checks, because only one of the document is signed.
    ///
    /// The signature covers the entitlement — the account, the plan and the expiry — and
    /// nothing around it. So a file edited by hand could pair a genuine free entitlement
    /// with a `subscription` claiming Pro, and every screen drawn from the unsigned half
    /// would be wrong while the signature verified perfectly. Refusing a document whose
    /// entitlement names a different account is what closes that.
    private func isBelievable(_ profile: Profile) -> Bool {
        verifier.isAuthentic(profile.entitlement) && profile.isInternallyConsistent
    }

    public func clear() {
        storage.set(nil, forKey: key)
    }
}

/// The real thing: the app's own defaults domain.
///
/// The thinnest possible adapter, holding no logic to get wrong, which is what lets
/// everything above it be tested without touching anybody's preferences.
public struct SystemDefaultsStorage: SessionStorage {
    private let suiteName: String?

    /// - Parameter suiteName: A defaults domain to use instead of the app's own.
    ///   Nothing but a test has a reason to pass one.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    /// `UserDefaults` is not `Sendable`, though it is documented as safe from any
    /// thread. Naming the domain rather than holding an instance keeps that promise
    /// checkable by the compiler instead of asserted in a comment.
    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func set(_ data: Data?, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}
