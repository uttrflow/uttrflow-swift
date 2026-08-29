public import struct Foundation.Date

/// How someone signed in.
///
/// Every case the backend can name stays here, always. Which ones are *offered* is a
/// separate question with a separate answer — see ``offered`` — because a provider we stop
/// showing a button for is not a provider whose existing sessions should stop decoding.
public enum SignInProvider: String, Sendable, Equatable, CaseIterable, Codable {
    case google
    case gitHub
    case apple

    /// The providers this build puts a button on screen for.
    ///
    /// Google alone for now. GitHub is built, tested and works end to end on both sides;
    /// it waits because every provider offered is a flow to keep working on every client,
    /// and there is nobody yet for whom the second one is the difference between signing
    /// in and not. Apple needs a paid developer account and is the only one that posts its
    /// callback as a form.
    ///
    /// Adding one back is this line and a pair of credentials in the deployment.
    public static let offered: [SignInProvider] = [.google]

    /// What the button says. Each provider dictates its own wording and Apple's is a
    /// trademark requirement rather than a preference.
    public var buttonTitle: String {
        switch self {
        case .google: "Continue with Google"
        case .gitHub: "Continue with GitHub"
        case .apple: "Sign in with Apple"
        }
    }
}

/// Who is signed in.
///
/// Deliberately thin. The backend knows more; the app needs only enough to greet the
/// user and to show which account a subscription belongs to.
public struct Account: Sendable, Equatable, Codable {
    public let identifier: String
    public let displayName: String?
    public let emailAddress: String?
    public let provider: SignInProvider

    /// Where to ask the backend for this person's picture, or `nil` when there is none.
    ///
    /// A path on our own API and never the provider's address, which the backend
    /// deliberately does not send: the app talks to one host, and an image fetched from
    /// Google's CDN would tell Google every time somebody opened their Mac. See
    /// `internal/account/avatar.go` in the backend for the whole of the reasoning.
    ///
    /// Absent from the copy of this type carried inside a signed entitlement, which names
    /// only the fields the signature covers — hence optional, and hence never used to
    /// decide anything.
    public let avatarPath: String?

    public init(
        identifier: String, displayName: String?, emailAddress: String?,
        provider: SignInProvider, avatarPath: String? = nil
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.emailAddress = emailAddress
        self.provider = provider
        self.avatarPath = avatarPath
    }
}

/// What the subscription allows.
public enum Plan: String, Sendable, Equatable, CaseIterable, Codable {
    case free
    case pro
}

/// A signed statement from the backend about who this is and what they may do.
///
/// Long-lived on purpose. Signing in needs a network exactly once; every launch after
/// that must work without one, because an app whose whole claim is that it runs on your
/// own machine cannot stop working on a plane. The expiry is a backstop against a
/// cancelled subscription running for ever, not a session timeout.
public struct Entitlement: Sendable, Equatable, Codable {
    public let account: Account
    public let plan: Plan
    public let expiresAt: Date
    /// The signature the app checks before believing any of the above. Verified against
    /// a public key compiled into the binary, so a cached entitlement can be trusted
    /// offline without asking anyone.
    public let signature: String

    public init(account: Account, plan: Plan, expiresAt: Date, signature: String) {
        self.account = account
        self.plan = plan
        self.expiresAt = expiresAt
        self.signature = signature
    }

    public func isCurrent(at moment: Date) -> Bool { expiresAt > moment }
}
