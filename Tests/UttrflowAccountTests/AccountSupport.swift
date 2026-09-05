// Shared fixtures for the account tests: in-memory storage, a credulous verifier, and signed entitlements.

import CryptoKit
import Foundation
import Synchronization

@testable import UttrflowAccount

/// Bytes in memory, so a store is tested without a defaults domain or anything that outlives the test.
final class MemoryStorage: SessionStorage {
    /// The bytes, by key.
    private let contents = Mutex<[String: Data]>([:])

    /// Starts holding `initial`.
    init(_ initial: [String: Data] = [:]) {
        contents.withLock { $0 = initial }
    }

    var keys: Set<String> { contents.withLock { Set($0.keys) } }

    /// The bytes under `key`.
    func data(forKey key: String) -> Data? {
        contents.withLock { $0[key] }
    }

    /// Stores `data` under `key`, or removes the key when `nil`.
    func set(_ data: Data?, forKey key: String) {
        contents.withLock { $0[key] = data }
    }
}

/// Unwraps the refresh outcome for a test.
extension ProfileRefresh {
    /// The newer copy, when there is one.
    var updatedProfile: Profile? {
        guard case .updated(let profile) = self else { return nil }
        return profile
    }
}

/// A verifier that believes anything, for a test that needs a store to keep what the signature refuses.
struct CredulousVerifier: EntitlementVerifying {
    func isAuthentic(_ entitlement: Entitlement) -> Bool { true }
}

/// One backend, one impostor, and entitlements signed by either; keys are made per run, never checked in.
enum Fixture {
    /// The fixed instant every fixture is dated from.
    static let noon = Date(timeIntervalSince1970: 1_700_000_000)

    /// The key the tests pretend the backend holds.
    static let backend = Curve25519.Signing.PrivateKey()

    /// Somebody else's key, which must never be believed.
    static let impostor = Curve25519.Signing.PrivateKey()

    static var verifier: Ed25519EntitlementVerifier {
        Ed25519EntitlementVerifier(publicKey: backend.publicKey)
    }

    /// An account for `identifier` at `provider`, with a fixed name and email.
    static func account(_ identifier: String = "u_1", provider: SignInProvider = .google) -> Account {
        Account(
            identifier: identifier, displayName: "Naveen", emailAddress: "n@example.com",
            provider: provider)
    }

    /// An entitlement signed by `key`, expiring `expiring` seconds after ``noon`` (negative: already gone).
    static func entitlement(
        expiring: TimeInterval, plan: Plan = .pro,
        account: Account = Fixture.account(),
        signedBy key: Curve25519.Signing.PrivateKey = Fixture.backend
    ) -> Entitlement {
        key.signing(
            Entitlement(
                account: account, plan: plan, expiresAt: noon.addingTimeInterval(expiring),
                signature: ""))
    }

    /// A profile around `entitlement` whose unsigned half agrees with it, so the cache does not refuse it.
    static func profile(
        for entitlement: Entitlement,
        validator: String? = "\"fixture\"",
        devices: [Profile.Device] = [Fixture.device()]
    ) -> Profile {
        Profile(
            account: entitlement.account,
            subscription: Profile.Subscription(
                plan: entitlement.plan, status: .active,
                currentPeriodEnd: entitlement.plan == .free ? nil : entitlement.expiresAt,
                effectivePlan: entitlement.plan,
                limits: Profile.Limits(monthlyMinutes: 120, customDictionaryEntries: 25)),
            devices: devices,
            entitlement: entitlement,
            fetchedAt: noon,
            validator: validator)
    }

    /// A device row for the profile's list.
    static func device(
        identifier: String = "d_1", platform: Profile.Platform = .macOS,
        name: String = "Naveen's MacBook Pro", isCurrent: Bool = true
    ) -> Profile.Device {
        Profile.Device(
            identifier: identifier, platform: platform, name: name, appVersion: "0.1.0",
            lastSeenAt: noon, isCurrent: isCurrent)
    }

    /// A cache holding `entitlement`, as a second launch's would; not an overload, so `nil` is unambiguous.
    static func cacheHolding(_ entitlement: Entitlement?) -> UserDefaultsProfileCache {
        cacheHolding(profile: entitlement.map { profile(for: $0) })
    }

    /// A cache already holding `profile`, or empty for `nil`.
    static func cacheHolding(profile: Profile?) -> UserDefaultsProfileCache {
        let storage = MemoryStorage()
        let cache = UserDefaultsProfileCache(storage: storage, verifier: verifier)
        if let profile { try? cache.save(profile) }
        return cache
    }
}
