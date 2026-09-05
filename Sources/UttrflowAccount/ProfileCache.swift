public import UttrflowCore
public import struct Foundation.Data

public import class Foundation.JSONDecoder
public import class Foundation.JSONEncoder
public import class Foundation.UserDefaults

/// The server's answer about this account, kept whole between launches. See `Docs/entitlements.md`.
public protocol ProfileCache: Sendable {
    /// The profile on this Mac, or `nil` for one not worth believing. Expiry is not considered here.
    func load() -> Profile?

    /// Keeps `profile` for later launches, refusing at the door what would not verify.
    func save(_ profile: Profile) throws(AccountError)

    /// Signs out, removing the profile and nothing else the user owns.
    func clear()
}

/// `UserDefaults` reduced to the two calls this store makes, so it is testable without a domain.
public protocol SessionStorage: Sendable {
    func data(forKey key: String) -> Data?

    /// Stores `data`, or removes the value when it is `nil`.
    func set(_ data: Data?, forKey key: String)
}

/// The profile, kept in `UserDefaults` as one JSON document with a signature inside it.
public struct UserDefaultsProfileCache: ProfileCache {
    /// Versioned, so a future shape can arrive beside this one rather than on top of it.
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
        guard let profile = storage.decoded(Profile.self, forKey: key), isBelievable(profile) else {
            return nil
        }
        return profile
    }

    public func save(_ profile: Profile) throws(AccountError) {
        guard isBelievable(profile) else { throw .sessionMalformed }
        storage.set(encoding: profile, forKey: key)
    }

    /// The signature is real and the document names its account. Not the plan — see `Docs/entitlements.md`.
    private func isBelievable(_ profile: Profile) -> Bool {
        verifier.isAuthentic(profile.entitlement) && profile.isInternallyConsistent
    }

    public func clear() {
        storage.set(nil, forKey: key)
    }
}

extension SessionStorage {
    /// The JSON document under `key` as a `Value`, or `nil` when there is none or it does not decode.
    func decoded<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Stores `value` as one JSON document; strings, enumerations and dates cannot fail to encode.
    func set(encoding value: some Encodable, forKey key: String) {
        set(try? JSONEncoder().encode(value), forKey: key)
    }
}

/// The app's own defaults domain, as an adapter thin enough to hold no logic to get wrong.
public struct SystemDefaultsStorage: SessionStorage {
    private let suiteName: String?

    /// - Parameter suiteName: Another defaults domain, which only a test has reason to pass.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    /// Named rather than held, so `UserDefaults` being thread-safe is checked, not asserted.
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
