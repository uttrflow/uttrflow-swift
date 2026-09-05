import CryptoKit
import Foundation
import Synchronization

@testable import UttrflowAccount

/// Bytes in memory, so a store's real behaviour is tested without a defaults domain,
/// a suite name, or anything that outlives the test.
final class MemoryStorage: SessionStorage {
    private let contents = Mutex<[String: Data]>([:])

    init(_ initial: [String: Data] = [:]) {
        contents.withLock { $0 = initial }
    }

    var keys: Set<String> { contents.withLock { Set($0.keys) } }

    func data(forKey key: String) -> Data? {
        contents.withLock { $0[key] }
    }

    func set(_ data: Data?, forKey key: String) {
        contents.withLock { $0[key] = data }
    }
}

extension ProfileRefresh {
    /// The newer copy, when there is one.
    var updatedProfile: Profile? {
        guard case .updated(let profile) = self else { return nil }
        return profile
    }
}

/// A verifier that believes anything, for the one test that needs a store to keep
/// something the signature would have refused.
struct CredulousVerifier: EntitlementVerifying {
    func isAuthentic(_ entitlement: Entitlement) -> Bool { true }
}

/// One backend, one impostor, and entitlements signed by either.
///
/// The keys are generated per run rather than checked in, for the same reason the
/// module has no keypair in it.
enum Fixture {
    static let noon = Date(timeIntervalSince1970: 1_700_000_000)

    /// The key the tests pretend the backend holds.
    static let backend = Curve25519.Signing.PrivateKey()

    /// Somebody else's key, which must never be believed.
    static let impostor = Curve25519.Signing.PrivateKey()

    static var verifier: Ed25519EntitlementVerifier {
        Ed25519EntitlementVerifier(publicKey: backend.publicKey)
    }

    static func account(_ identifier: String = "u_1", provider: SignInProvider = .google) -> Account {
        Account(
            identifier: identifier, displayName: "Naveen", emailAddress: "n@example.com",
            provider: provider)
    }

    /// - Parameters:
    ///   - expiring: Seconds from ``noon`` at which the entitlement runs out. Negative
    ///     for one that already has.
    ///   - plan: What it entitles its holder to.
    ///   - account: Who it belongs to.
    ///   - key: Whose key signs it. Anything but ``backend`` must not be believed.
    /// - Returns: A fully signed entitlement.
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

    /// A whole profile wrapped around `entitlement`.
    ///
    /// The unsigned half is filled in consistently with the signed one — same account,
    /// same plan — because a profile whose two halves disagree is refused by the cache,
    /// and a fixture that produced one would fail every test for the wrong reason.
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

    static func device(
        identifier: String = "d_1", platform: Profile.Platform = .macOS,
        name: String = "Naveen's MacBook Pro", isCurrent: Bool = true
    ) -> Profile.Device {
        Profile.Device(
            identifier: identifier, platform: platform, name: name, appVersion: "0.1.0",
            lastSeenAt: noon, isCurrent: isCurrent)
    }

    /// A cache already holding `entitlement`, as a Mac on its second launch would be.
    ///
    /// Two functions rather than one overloaded on an optional: `cacheHolding(nil)` would
    /// otherwise be ambiguous, and the ambiguity would be reported at every call site that
    /// tests the signed-out case.
    static func cacheHolding(_ entitlement: Entitlement?) -> UserDefaultsProfileCache {
        cacheHolding(profile: entitlement.map { profile(for: $0) })
    }

    static func cacheHolding(profile: Profile?) -> UserDefaultsProfileCache {
        let storage = MemoryStorage()
        let cache = UserDefaultsProfileCache(storage: storage, verifier: verifier)
        if let profile { try? cache.save(profile) }
        return cache
    }
}
