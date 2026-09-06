// A backend that is not there: a development authentication service signing with a per-process key.
public import UttrflowCore
public import CryptoKit

public import struct Foundation.Data
public import struct Foundation.Date
public import struct Foundation.URL
public import typealias Foundation.TimeInterval

public import struct Foundation.URLComponents
public import struct Foundation.URLQueryItem
public import struct Foundation.UUID

private import Synchronization

/// Runs the real shape of sign-in against no server, signing with a per-process Ed25519 key.
public final class InMemoryAuthenticationService: AuthenticationService {
    /// A month: the backstop that stops a cancelled subscription running for ever, not a session timeout.
    public static let defaultLifetime: TimeInterval = 30 * 24 * 60 * 60

    /// A host in the reserved `.invalid` domain, so the app rehearses opening a page that resolves nowhere.
    public static let developmentEndpoint = safeURL("https://sign-in.invalid/uttrflow")

    /// Everything that changes, behind a `Mutex` because nothing done with it is slow enough for an actor.
    private struct Progress: Sendable {
        /// The state the next ``completeSignIn(_:)`` must echo.
        var pendingState: String?
        /// The profile handed out, so re-reading answers the same thing twice.
        var issued: Profile?
    }

    /// Signs every entitlement; fresh per process unless a caller keeps one.
    private let signingKey: Curve25519.Signing.PrivateKey
    /// What every sign-in here is entitled to.
    private let plan: Plan
    /// How long a minted entitlement lasts.
    private let lifetime: TimeInterval
    /// The address a sign-in pretends to visit.
    private let endpoint: URL
    /// The clock, injected so a test can move it.
    private let now: @Sendable () -> Date
    /// The attempt in flight and the profile issued.
    private let progress = Mutex(Progress())

    /// Every default is the development app's; only a test passes `now`, and a key only survives if kept.
    public init(
        plan: Plan = .pro,
        lifetime: TimeInterval = InMemoryAuthenticationService.defaultLifetime,
        endpoint: URL = InMemoryAuthenticationService.developmentEndpoint,
        signingKey: Curve25519.Signing.PrivateKey = Curve25519.Signing.PrivateKey(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.plan = plan
        self.lifetime = lifetime
        self.endpoint = endpoint
        self.signingKey = signingKey
        self.now = now
    }

    /// The verifier that believes what this service signs, so the development signature check stays live.
    public var verifier: Ed25519EntitlementVerifier {
        Ed25519EntitlementVerifier(publicKey: signingKey.publicKey)
    }

    /// Issues a state and a page to open.
    public func beginSignIn(with provider: SignInProvider) async throws(AccountError) -> SignInChallenge {
        let state = UUID().uuidString
        progress.withLock { $0.pendingState = state }
        return SignInChallenge(
            authorisationURL: authorisationURL(for: provider, state: state), state: state)
    }

    /// Mints a profile for the attempt whose state matches; a mismatch is refused, as in the release build.
    public func completeSignIn(_ challenge: SignInChallenge) async throws(AccountError) -> Profile {
        guard let expected = progress.take(\.pendingState), expected == challenge.state else {
            throw .providerRefused(description: "that sign-in does not answer this attempt")
        }
        let profile = mint(
            for: Account(
                identifier: "dev-\(challenge.state.prefix(8))", displayName: "Development User",
                emailAddress: "developer@uttrflow.invalid", provider: .google))
        progress.withLock { $0.issued = profile }
        return profile
    }

    /// No pictures: a backend can be stood in for, somebody's face cannot.
    public func avatar(at path: String) async -> Data? { nil }

    /// `unchanged` for the last minted copy, `updated` for anybody else, `noCredential` before any minting.
    public func currentProfile(ifChangedFrom cached: Profile?) async throws(AccountError) -> ProfileRefresh {
        // Nothing minted yet is "no credential on this Mac", not a sign-out, so the cached profile survives.
        guard let issued = progress.withLock({ $0.issued }) else { return .noCredential }
        if let cached, cached.validator != nil, cached.validator == issued.validator {
            return .unchanged
        }
        let renewed = mint(for: issued.account)
        progress.withLock { $0.issued = renewed }
        return .updated(renewed)
    }

    /// Forgets the issued profile.
    public func signOut() async {
        progress.withLock { $0.issued = nil }
    }

    /// A whole signed profile, invented where the real one is read from a database, with a fresh validator.
    private func mint(for account: Account) -> Profile {
        let entitlement = signingKey.signing(
            Entitlement(
                account: account, plan: plan, expiresAt: now().addingTimeInterval(lifetime),
                signature: ""))
        return Profile(
            account: account,
            subscription: Profile.Subscription(
                plan: plan, status: .active,
                currentPeriodEnd: plan == .free ? nil : now().addingTimeInterval(lifetime),
                effectivePlan: plan,
                limits: Profile.Limits(
                    monthlyMinutes: plan == .free ? 120 : nil,
                    customDictionaryEntries: plan == .free ? 25 : nil)),
            devices: [
                Profile.Device(
                    identifier: UUID().uuidString, platform: .macOS, name: "This Mac",
                    appVersion: nil, lastSeenAt: now(), isCurrent: true)
            ],
            entitlement: entitlement,
            fetchedAt: now(),
            validator: "\"development-\(UUID().uuidString)\"")
    }

    /// The endpoint with the provider and state attached.
    private func authorisationURL(for provider: SignInProvider, state: String) -> URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "provider", value: provider.rawValue),
            URLQueryItem(name: "state", value: state),
        ]
        // The bare endpoint stands in if two query items somehow cannot be attached to it.
        return components?.url ?? endpoint
    }
}

/// A `URL` from a literal without a force unwrap; the path fallback is unreachable for every literal here.
func safeURL(_ string: String) -> URL {
    URL(string: string) ?? URL(filePath: string)
}
