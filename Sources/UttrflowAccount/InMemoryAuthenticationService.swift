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

/// A backend that is not there: enough of one to run the whole app while the real one
/// is being written.
///
/// It is not a stub that returns a constant. It runs the real shape of the exchange —
/// a challenge, a state value that must come back matching, a signed entitlement with a
/// real expiry — and it signs with a genuine Ed25519 key so that every line of
/// ``Ed25519EntitlementVerifier`` is exercised in development rather than first meeting
/// a signature on the day of release.
///
/// The key pair is generated in this process and never written anywhere, which is why
/// there is no keypair in this repository to leak. It also means a session cached by
/// one run is not believed by the next, because the next run has a different key: for a
/// development session that survives a relaunch, pass a `signingKey` your own
/// environment supplies.
///
/// **The real one is ``HTTPAuthenticationService``**, which does the same four steps
/// against a deployed backend. Which of the two a build uses is decided once, in
/// `OnboardingAccountLayer.forThisBuild()`, by whether there is an address to reach and a
/// public key to check what comes back. Nothing else in this module knows the difference:
/// the cache, the gate and the verifier never learn that the backend became real.
public final class InMemoryAuthenticationService: AuthenticationService {
    /// A month.
    ///
    /// Long by the standards of a session and short by the standards of a subscription,
    /// which is what an entitlement is: the backstop that stops a cancelled
    /// subscription running for ever, not a timer that logs anybody out.
    public static let defaultLifetime: TimeInterval = 30 * 24 * 60 * 60

    /// A host in the reserved `.invalid` domain, which by definition resolves nowhere.
    ///
    /// The app under development opens this exactly as it will open the real one, so
    /// the code path is rehearsed; nothing answers, and nothing needs to, because this
    /// service completes its own exchange. The real endpoint belongs to whoever deploys
    /// the backend and compiling one in here — with the client identifier it would need
    /// — is precisely what this module must not do.
    public static let developmentEndpoint = safeURL("https://sign-in.invalid/uttrflow")

    /// Everything that changes. A `Mutex` rather than an actor because the service is
    /// asked questions from wherever the sign-in window happens to be running, and
    /// nothing it does is slow enough to be worth a suspension.
    private struct Progress: Sendable {
        var pendingState: String?
        /// The profile this service has handed out, so that re-reading it answers the
        /// same thing twice — which is what makes it a source of truth rather than a
        /// generator of plausible values.
        var issued: Profile?
    }

    private let signingKey: Curve25519.Signing.PrivateKey
    private let plan: Plan
    private let lifetime: TimeInterval
    private let endpoint: URL
    private let now: @Sendable () -> Date
    private let progress = Mutex(Progress())

    /// - Parameters:
    ///   - plan: What every sign-in here is entitled to.
    ///   - lifetime: How long a minted entitlement lasts.
    ///   - endpoint: The address a sign-in pretends to visit.
    ///   - signingKey: The key entitlements are signed with. A fresh one per process
    ///     unless a caller has somewhere to keep one.
    ///   - now: The clock. Only a test has a reason to pass one.
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

    /// The verifier that believes what this service signs.
    ///
    /// Wire the development app with this and the signature check is live rather than
    /// switched off — an "accept everything" verifier for development is how a build
    /// ships with no check at all.
    public var verifier: Ed25519EntitlementVerifier {
        Ed25519EntitlementVerifier(publicKey: signingKey.publicKey)
    }

    public func beginSignIn(with provider: SignInProvider) async throws(AccountError) -> SignInChallenge {
        let state = UUID().uuidString
        progress.withLock { $0.pendingState = state }
        return SignInChallenge(
            authorisationURL: authorisationURL(for: provider, state: state), state: state)
    }

    /// The state check is real, not decorative. A development build that answered a
    /// challenge it had not issued would be rehearsing a flow the release build does not
    /// have.
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

    /// Answers `unchanged` for a caller holding the copy this service last minted, and a
    /// fresh one for anybody else — the same two answers the real backend gives, so the
    /// caching path is rehearsed rather than met for the first time on release day.
    /// No pictures. This service stands in for a backend, and the one thing it cannot
    /// stand in for is somebody's face.
    public func avatar(at path: String) async -> Data? { nil }

    public func currentProfile(ifChangedFrom cached: Profile?) async throws(AccountError) -> ProfileRefresh {
        // Nothing minted here yet, which for a service that forgets everything when the
        // process ends is every launch after the first. That is "no credential on this
        // Mac", not "the server ended your session", and a development build must not
        // delete its cached profile over it any more than a release build does.
        guard let issued = progress.withLock({ $0.issued }) else { return .noCredential }
        if let cached, cached.validator != nil, cached.validator == issued.validator {
            return .unchanged
        }
        let renewed = mint(for: issued.account)
        progress.withLock { $0.issued = renewed }
        return .updated(renewed)
    }

    public func signOut() async {
        progress.withLock { $0.issued = nil }
    }

    /// A whole profile, signed where the real one is signed and invented where the real
    /// one is read from a database.
    ///
    /// The validator is a fresh value each time, which is what makes the `unchanged` path
    /// above testable: a caller holding the previous copy is told it is current, and one
    /// holding nothing is given a new document with a new tag.
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

/// Builds a `URL` from a literal without a force unwrap, which this package forbids.
///
/// The fallback treats the string as a path. It is unreachable for every literal in this
/// module, and a nonsense URL is in any case a better outcome than a crash on launch.
func safeURL(_ string: String) -> URL {
    URL(string: string) ?? URL(filePath: string)
}
