// The dictation gate: whether this person may dictate now.
public import struct Foundation.Date

/// What Uttrflow may do for this person now, as four answers because three of them permit a dictation.
public enum DictationAccess: Sendable, Equatable, CaseIterable {
    /// Nobody signed in: the one answer that stops a dictation and every surface but sign-in.
    case refused

    /// Signed in, with a current account-validation record. Nothing to say.
    case allowed

    /// Aged out with no connection to renew on, and dictation continues. See `Docs/entitlements.md`.
    case allowedAwaitingNetwork

    /// Aged out with a connection: worth a prompt, never worth a dictation.
    case allowedPendingSignIn

    /// Whether a dictation may start, as a `switch` so a new state cannot skip the decision.
    public var permitsDictation: Bool {
        switch self {
        case .refused: false
        case .allowed, .allowedAwaitingNetwork, .allowedPendingSignIn: true
        }
    }
}

/// The one thing the rest of the app asks: may this person dictate? See `Docs/entitlements.md`.
public struct EntitlementGate: Sendable {
    /// The signed half of what is known.
    private let profiles: any ProfileCache

    /// Reads the session from `profiles` and nothing else.
    public init(profiles: any ProfileCache) {
        self.profiles = profiles
    }

    /// `networkIsReachable` changes only what the user is told, never whether they may speak.
    public func access(at moment: Date, networkIsReachable: Bool) -> DictationAccess {
        // The signed half only: no permission is read from a field the backend did not sign.
        guard let entitlement = profiles.load()?.entitlement else { return .refused }
        if entitlement.isCurrent(at: moment) { return .allowed }
        return networkIsReachable ? .allowedPendingSignIn : .allowedAwaitingNetwork
    }
}
