public import struct Foundation.Date

/// What Uttrflow may do for this person, right now.
///
/// Four answers rather than a boolean, because three of them permit a dictation and
/// mean entirely different things to the interface: one is silence, one is a quiet note
/// that the subscription could not be checked, and one is an invitation to sign in
/// again. Collapsing them loses the difference between "we could not ask" and "we asked
/// and you should do something", and the only way to collapse them safely is to make
/// the third refuse — which is the failure this module exists to prevent.
public enum DictationAccess: Sendable, Equatable, CaseIterable {
    /// Nobody has signed in on this Mac and nobody chose to do without. The one answer
    /// that stops a dictation, and the only state in which a network is genuinely
    /// required.
    case refused

    /// Signed in, subscription current. Nothing to say.
    case allowed

    /// Nobody is signed in, and somebody chose this Mac instead — see ``LocalAccount``.
    ///
    /// Its own case rather than ``allowed``, because the two are the same permission and
    /// entirely different situations: one has a signed statement from the backend behind
    /// it and one has a person's decision. Every screen that says who is here has to be
    /// able to tell them apart, and a boolean cannot.
    case allowedOnThisMac

    /// The entitlement has aged out and there is no connection to renew it on.
    ///
    /// Dictation continues. There is nothing to ask of somebody on a train, and holding
    /// their own words hostage to a server neither of you can reach is the worst thing
    /// this product could do. Ask again when there is a network.
    case allowedAwaitingNetwork

    /// The entitlement has aged out and there is a connection.
    ///
    /// Dictation continues here too. The renewal is worth attempting and the user is
    /// worth asking, but neither is worth a dictation: the answer is a prompt, never a
    /// door.
    case allowedPendingSignIn

    /// Whether a dictation may start.
    ///
    /// A `switch` rather than a comparison, so a fifth state cannot be added without
    /// somebody deciding, in this file, whether it costs the user their voice.
    public var permitsDictation: Bool {
        switch self {
        case .refused: false
        case .allowed, .allowedOnThisMac, .allowedAwaitingNetwork, .allowedPendingSignIn: true
        }
    }
}

/// The one thing the rest of the app asks: may this person dictate?
///
/// The product's four rules, as code rather than as comments:
///
/// 1. The first launch needs a network — there is no session yet, so ``refused``, and
///    the sign-in that follows is the only thing in this module that reaches a server.
///    Unless the person declined to have one, which is rule 5.
/// 2. Every launch after it does not — a cached entitlement is read from the disk and
///    believed on its signature, and nothing here asks anybody's permission.
/// 3. An expired entitlement degrades, never locks — both aged-out answers permit a
///    dictation, and the difference between them is only what the interface says.
/// 4. Signing out keeps local data — this type can reach a ``ProfileCache`` and nothing
///    else that holds words, so there is no code path from signing out to somebody's
///    history.
/// 5. A person who cannot sign in is not locked out — a ``LocalAccount`` is a way to work
///    on this Mac without an Uttrflow account, and it permits a dictation. It is checked
///    *after* the entitlement, never before: somebody with a real session gets the answer
///    their session earns, and the local account behind it changes nothing about it.
///
/// It performs no I/O beyond those two reads and it takes the moment and the network as
/// arguments, so all five rules are decided by a pure function that a test can put in
/// any state in one line.
public struct EntitlementGate: Sendable {
    private let profiles: any ProfileCache
    private let local: (any LocalAccountStore)?

    /// - Parameters:
    ///   - profiles: The signed profile on this Mac.
    ///   - local: Where the choice to work without an account is kept. Optional, and
    ///     absent means only what it says — no local account was chosen — so a caller
    ///     that has no store behaves exactly as this type did before there was one.
    public init(profiles: any ProfileCache, local: (any LocalAccountStore)? = nil) {
        self.profiles = profiles
        self.local = local
    }

    /// - Parameters:
    ///   - moment: Now. Passed in rather than read, so that "expired an hour ago" and
    ///     "expired five years ago" are one line apart in a test.
    ///   - networkIsReachable: Whether a renewal could even be attempted. Only ever
    ///     changes *what the user is told*, never whether they may speak — which is why
    ///     it is a plain answer from the caller and not a reachability monitor this
    ///     module would have to own.
    /// - Returns: What Uttrflow may do for this person, of which three of the four
    ///   answers permit a dictation.
    public func access(at moment: Date, networkIsReachable: Bool) -> DictationAccess {
        // The signed half of the profile, and only the signed half. What somebody may do
        // is never read from a field the backend did not sign.
        guard let entitlement = profiles.load()?.entitlement else {
            // No session. The last question is whether this person chose to do without
            // one — an answer that is theirs to give and is not a subscription, which is
            // why it is asked here and nowhere a plan is read.
            return local?.load() == nil ? .refused : .allowedOnThisMac
        }
        if entitlement.isCurrent(at: moment) { return .allowed }
        return networkIsReachable ? .allowedPendingSignIn : .allowedAwaitingNetwork
    }
}
