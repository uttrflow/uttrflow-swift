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

/// Who is signed in: only enough to greet the person and identify the signed-in account.
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

    /// When the backend created the account, or `nil` when it did not say; displayed, never enforced.
    public let createdAt: Date?

    /// Assembles an account; the avatar path and the creation date default to none.
    public init(
        identifier: String, displayName: String?, emailAddress: String?,
        provider: SignInProvider, avatarPath: String? = nil, createdAt: Date? = nil
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.emailAddress = emailAddress
        self.provider = provider
        self.avatarPath = avatarPath
        self.createdAt = createdAt
    }

    /// The wire keys; `createdAt` is an ISO-8601 string, as the backend writes it.
    private enum CodingKeys: String, CodingKey {
        case identifier, displayName, emailAddress, provider, avatarPath, createdAt
    }

    /// Decodes the account; an unreadable creation date reads as none rather than failing the document.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(String.self, forKey: .identifier)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        emailAddress = try container.decodeIfPresent(String.self, forKey: .emailAddress)
        provider = try container.decode(SignInProvider.self, forKey: .provider)
        avatarPath = try container.decodeIfPresent(String.self, forKey: .avatarPath)
        createdAt = try? Timestamp.decodeIfPresent(from: container, forKey: .createdAt)
    }

    /// Encodes the account with the creation date as a string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(emailAddress, forKey: .emailAddress)
        try container.encode(provider, forKey: .provider)
        try container.encodeIfPresent(avatarPath, forKey: .avatarPath)
        try container.encodeIfPresent(createdAt.map(Timestamp.string(from:)), forKey: .createdAt)
    }
}

/// The signed account-validation record received from the backend.
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
    /// The validity of the signed account record, not the session timeout.
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
