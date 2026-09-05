/// What goes wrong before there is a session; an expired entitlement is not here, dictation carries on.
public enum AccountError: UttrflowFailure {
    /// The first sign-in on this Mac needs a network and has none; later launches read a cached entitlement.
    case serverUnreachable

    /// The provider was reached, and said no.
    case providerRefused(description: String)

    /// Something claiming to be an entitlement does not verify against the key this build carries.
    case sessionMalformed

    /// The sign-in worked but the Keychain would not hold the token, so the session ends at the next launch.
    case sessionCouldNotBeKept

    /// A plain sentence for each case, never naming the provider.
    public var userMessage: String {
        switch self {
        case .serverUnreachable:
            "Uttrflow needs an internet connection the first time you sign in."
        case .providerRefused:
            "Uttrflow could not confirm that sign-in."
        case .sessionMalformed:
            "Uttrflow could not confirm your subscription on this Mac."
        case .sessionCouldNotBeKept:
            "Uttrflow could not save your sign-in on this Mac."
        }
    }

    /// A retry, which the interface turns into a fresh sign-in, for every case a retry can change.
    public var recovery: RecoveryAction? {
        switch self {
        // A connection may well have appeared since; that is the whole remedy.
        case .serverUnreachable: .retry
        // Another attempt, or another provider; the user has a real choice to make.
        case .providerRefused: .retry
        // A signature that does not verify means this build carries the wrong key, which no retry changes.
        case .sessionMalformed: nil
        // A Keychain refusal is usually a locked keychain or a transient error, which a second try clears.
        case .sessionCouldNotBeKept: .retry
        }
    }

    /// Blocking for all four: each leaves the Mac with no session, and dictation requires one.
    public var severity: FailureSeverity {
        switch self {
        case .serverUnreachable, .providerRefused, .sessionMalformed, .sessionCouldNotBeKept:
            .blocking
        }
    }
}
