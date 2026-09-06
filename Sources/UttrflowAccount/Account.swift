// The account, the providers that can sign one in, and the signed entitlement.
public import struct Foundation.Date

/// How someone signed in; every case the backend can name stays, whether or not ``offered`` shows it.
public enum SignInProvider: String, Sendable, Equatable, CaseIterable, Codable {
    case google
    case gitHub
    case apple

    /// The providers with a button on screen; adding one is this line plus a pair of deployment credentials.
    public static let offered: [SignInProvider] = [.google]

    /// What the button says; each provider dictates its wording, and Apple's is a trademark requirement.
    public var buttonTitle: String {
        switch self {
        case .google: "Continue with Google"
        case .gitHub: "Continue with GitHub"
        case .apple: "Sign in with Apple"
        }
    }
}

/// Who is signed in: only enough to greet the person and name which account a subscription belongs to.
public struct Account: Sendable, Equatable, Codable {
    /// The backend's identifier for this account.
    public let identifier: String
    /// The name to greet them by, if the provider gave one.
    public let displayName: String?
    /// Their email address, if the provider gave one.
    public let emailAddress: String?
    /// How they signed in.
    public let provider: SignInProvider

    /// A path on our own API for the picture, or `nil`; never the provider's host, and decides nothing.
    public let avatarPath: String?

    /// Assembles an account; the avatar path defaults to none.
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

/// The backend's signed statement of who this is and what they may do, kept long so launches work offline.
public struct Entitlement: Sendable, Equatable, Codable {
    /// Who this is signed for.
    public let account: Account
    /// What they may do.
    public let plan: Plan
    /// A backstop against a cancelled subscription running for ever, not a session timeout.
    public let expiresAt: Date
    /// Checked against a public key compiled into the binary, so a cached entitlement is trusted offline.
    public let signature: String

    /// Assembles an entitlement as the backend signed it.
    public init(account: Account, plan: Plan, expiresAt: Date, signature: String) {
        self.account = account
        self.plan = plan
        self.expiresAt = expiresAt
        self.signature = signature
    }

    /// Whether the expiry is still ahead of `moment`.
    public func isCurrent(at moment: Date) -> Bool { expiresAt > moment }
}
