public import struct Foundation.Date

/// What Uttrflow may do for this person now, as five answers because four of them permit a dictation.
public enum DictationAccess: Sendable, Equatable, CaseIterable {
    /// Nobody signed in and nobody chose to do without: the one answer that stops a dictation.
    case refused

    /// Signed in, subscription current. Nothing to say.
    case allowed

    /// Nobody signed in and somebody chose this Mac instead — the same permission, a different situation.
    case allowedOnThisMac

    /// Aged out with no connection to renew on, and dictation continues. See `Docs/entitlements.md`.
    case allowedAwaitingNetwork

    /// Aged out with a connection: worth a prompt, never worth a dictation.
    case allowedPendingSignIn

    /// Whether a dictation may start, as a `switch` so a new state cannot skip the decision.
    public var permitsDictation: Bool {
        switch self {
        case .refused: false
        case .allowed, .allowedOnThisMac, .allowedAwaitingNetwork, .allowedPendingSignIn: true
        }
    }
}

/// The one thing the rest of the app asks: may this person dictate? See `Docs/entitlements.md`.
public struct EntitlementGate: Sendable {
    private let profiles: any ProfileCache
    private let local: (any LocalAccountStore)?

    public init(profiles: any ProfileCache, local: (any LocalAccountStore)? = nil) {
        self.profiles = profiles
        self.local = local
    }

    /// `networkIsReachable` changes only what the user is told, never whether they may speak.
    public func access(at moment: Date, networkIsReachable: Bool) -> DictationAccess {
        // The signed half only: no permission is read from a field the backend did not sign.
        guard let entitlement = profiles.load()?.entitlement else {
            // No session, so the last question is whether they chose to do without one.
            return local?.load() == nil ? .refused : .allowedOnThisMac
        }
        if entitlement.isCurrent(at: moment) { return .allowed }
        return networkIsReachable ? .allowedPendingSignIn : .allowedAwaitingNetwork
    }
}
