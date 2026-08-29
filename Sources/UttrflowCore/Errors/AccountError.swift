/// What can go wrong getting somebody signed in.
///
/// Every case here happens *before* there is a session, which is why all three are
/// blocking: without a session there is no dictation, and saying anything softer would
/// be describing a product that carried on. What is deliberately **not** here is an
/// expired entitlement. That is not a failure — it is the ordinary state of a Mac that
/// has been offline for a while, and ``DictationAccess`` answers it by carrying on. An
/// error case for it is exactly how a degrade turns into a lock-out.
///
/// This lives beside the module it comes from rather than in ``UttrflowCore`` with every
/// other failure, which is where ``HistoryStoreError`` explains they all belong.
/// ``FailureCatalogue`` cannot reach upwards into a module that depends on it, so until
/// this file moves down into Core the catalogue cannot see these three and nothing but
/// this module's own tests proves they have a sentence for the user. The
/// ``CataloguedFailure`` conformance below is written as though the move had already
/// happened, so that the move is the whole of the change.
public enum AccountError: UttrflowFailure {
    /// The first sign-in on this Mac needed a network and there was not one.
    ///
    /// Only ever the *first*: every launch after it reads a cached entitlement and asks
    /// nobody's permission, so this sentence can afford to name the one occasion it
    /// applies to instead of hedging.
    case serverUnreachable

    /// The provider was reached, and said no.
    case providerRefused(description: String)

    /// Something claiming to be an entitlement could not be believed — the signature
    /// did not check out against the key this build carries.
    case sessionMalformed

    /// The sign-in worked and the session could not be kept.
    ///
    /// Its own case because it is the opposite of every other one here: nothing was
    /// refused and nothing was malformed — the Keychain would not hold the token. A
    /// session that cannot be stored is a session that ends at the next launch, so
    /// reporting the sign-in as successful is a lie the user discovers later, having
    /// been shown their own account in between.
    case sessionCouldNotBeKept

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

    /// - Note: ``RecoveryAction`` has no "sign in" case, so the two recoverable
    ///   failures here offer ``RecoveryAction/retry`` and the interface restarts the
    ///   sign-in behind it. A dedicated case belongs in ``UttrflowCore`` and would read
    ///   better on the button.
    public var recovery: RecoveryAction? {
        switch self {
        // A connection may well have appeared since; that is the whole remedy.
        case .serverUnreachable: .retry
        // Another attempt, or another provider — the user has a real choice to make.
        case .providerRefused: .retry
        // Nothing offered, deliberately. A signature that does not check out means this
        // build and the backend disagree about the key, and no number of attempts by
        // the user changes which key was compiled in. A Retry button here would be a
        // button that cannot work.
        case .sessionMalformed: nil
        // Worth another attempt: the Keychain refusing a write is usually a locked
        // keychain or a transient refusal, both of which a second try can clear.
        case .sessionCouldNotBeKept: .retry
        }
    }

    /// All four blocking, and not for want of thought: each one leaves the Mac with no
    /// session at all, and dictation requires one. The severities that vary in this
    /// product are the ones where the words still arrived.
    public var severity: FailureSeverity {
        switch self {
        case .serverUnreachable, .providerRefused, .sessionMalformed, .sessionCouldNotBeKept:
            .blocking
        }
    }
}
