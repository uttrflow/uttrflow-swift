public import UttrflowCore
public import struct Foundation.Data
public import struct Foundation.URL

/// How this sign-in is going to finish.
///
/// Two ways, and the app does not choose between them — the machine does. A Mac that can
/// bind a loopback port gets the browser back automatically; one that cannot has to be
/// given a code to type, because there is nowhere for the browser to return to.
///
/// The second is not a lesser path or a fallback in the apologetic sense. It is RFC 8628,
/// it is how a television signs you in, and it works on a locked-down laptop, over SSH,
/// and in a terminal client we have not written yet.
public enum SignInMethod: Sendable, Equatable {
    /// The browser will come back to a port this app is listening on.
    case browser

    /// The person types a short code into a browser, here or on another machine.
    case code(userCode: String, verificationURL: URL)

    /// The code to show, when there is one.
    public var userCode: String? {
        guard case .code(let userCode, _) = self else { return nil }
        return userCode
    }
}

/// A sign-in that has started in a browser and not yet finished.
///
/// Deliberately holds nothing secret. The PKCE verifier that will spend the authorization
/// code stays inside the service that made it and never reaches this value, so a challenge
/// can be held by the interface, compared, logged during a support investigation, and
/// still be worth nothing to anybody who reads it.
public struct SignInChallenge: Sendable, Equatable {
    /// The page the app opens in the user's own browser.
    public let authorisationURL: URL

    /// Identifies this attempt. It travels *through the browser*, so it must be assumed
    /// public: its only job is to prove that an answer belongs to the sign-in in flight
    /// rather than to one somebody else started.
    public let state: String

    /// How it will finish, decided when it started rather than guessed at afterwards.
    public let method: SignInMethod

    public init(authorisationURL: URL, state: String, method: SignInMethod = .browser) {
        self.authorisationURL = authorisationURL
        self.state = state
        self.method = method
    }
}

/// What re-reading the profile found.
///
/// Three answers rather than an optional, because "nothing has changed" and "you are no
/// longer signed in" are opposite outcomes that an optional would collapse into the same
/// `nil`. One means keep everything; the other means the session was ended, probably from
/// another machine by somebody who had just lost this one.
public enum ProfileRefresh: Sendable, Equatable {
    /// The server confirmed the cached copy is current. Nothing to write.
    case unchanged

    /// A newer copy, to be cached in place of whatever was there.
    case updated(Profile)

    /// The server no longer recognises this session: signed out from another device, or
    /// this device forgotten. Distinct from every failure case, because it is not one —
    /// it is an instruction, and the app carries it out by signing out locally.
    case signedOut

    /// There is no credential on this Mac to ask with, so the server was not asked.
    ///
    /// Separate from ``signedOut`` because the two are opposites in the only way that
    /// matters: that one is the server saying "this session is over", and this one is the
    /// server saying nothing at all. Collapsing them is how a Keychain entry that is not
    /// there — a signing identity that changed, an ad-hoc build rebuilt since the last
    /// sign-in — turns into a cached profile being deleted at the next launch, which is
    /// the one failure the profile was kept out of the Keychain to prevent. See
    /// ``ProfileCache`` for that argument, and ``KeychainTokenStore`` for when an entry
    /// goes missing.
    case noCredential

    /// The newer copy, when there is one. For callers that want the profile rather than
    /// the distinction between the two ways there can fail to be a new one.
    public var updatedProfile: Profile? {
        guard case .updated(let profile) = self else { return nil }
        return profile
    }
}

/// The backend, as the rest of the app is allowed to see it.
///
/// Sign-in is the authorization-code flow of RFC 8252, the IETF's best practice for native
/// applications:
///
/// 1. ``beginSignIn(with:)`` binds a listener on `127.0.0.1`, invents a PKCE verifier it
///    keeps, and answers with a page to open.
/// 2. The user signs in, in their own browser. The provider returns to our backend, which
///    runs the exchange with credentials that never leave it.
/// 3. The backend redirects the browser to the port this app is listening on, carrying a
///    single-use authorization code.
/// 4. ``completeSignIn(_:)`` spends that code with the verifier from step one, and reads
///    the profile.
///
/// The code is worthless to anybody who intercepts it, because spending it requires a
/// value that never left this process. The alternative — a custom URL scheme — needs
/// per-platform registration, can be claimed by any other application on the machine, and
/// is why this app registered `uttrflow://` once and no longer does.
///
/// Every call here needs a network. Nothing else in this module does, which is the point:
/// this protocol is the only place the offline promise can be broken, so it is the only
/// place to look when checking that it has not been.
public protocol AuthenticationService: Sendable {
    /// Starts a sign-in. Hand the returned URL to the browser, keep the challenge.
    ///
    /// The challenge says how it will finish. A Mac that cannot bind a loopback port —
    /// locked down, or running this over a remote session — gets a code to show instead of
    /// a redirect to wait for, and the interface has to be ready to draw one.
    func beginSignIn(with provider: SignInProvider) async throws(AccountError) -> SignInChallenge

    /// Waits for the browser half to finish, then collects the session and the profile.
    ///
    /// Returns when the person has signed in, which may be a minute after the call — they
    /// have a password manager to find. Cancelling the surrounding task abandons the
    /// attempt; the browser tab stays open, because nothing here can close it.
    ///
    /// - Throws: ``AccountError/serverUnreachable`` when there is no connection, which on a
    ///   first launch is the failure the user must be told about plainly;
    ///   ``AccountError/providerRefused(description:)`` when the sign-in was answered and
    ///   refused, or expired before it finished.
    func completeSignIn(_ challenge: SignInChallenge) async throws(AccountError) -> Profile

    /// Re-reads the profile, sending the cached copy's validator so that an unchanged one
    /// costs a header rather than a document.
    ///
    /// Called on launch and periodically after it. Never on the path that decides whether
    /// somebody may dictate: a failure here costs nothing, because the cached entitlement
    /// keeps working either way.
    func currentProfile(ifChangedFrom cached: Profile?) async throws(AccountError) -> ProfileRefresh

    /// Fetches the picture at a path the profile named, or `nil` when there is none.
    ///
    /// The path comes from the document rather than being written here, and the bytes come
    /// from our own backend rather than from the provider — the app opens sockets to one
    /// host, and this is not the place to make an exception. See ``Account/avatarPath``.
    ///
    /// Answers `nil` rather than throwing for anything short of a broken session. A
    /// missing face is not a failure worth a message: the interface draws initials, which
    /// is what it draws before the fetch finishes anyway.
    func avatar(at path: String) async -> Data?

    /// Ends this machine's session at the server, and forgets the credential locally.
    ///
    /// Does not throw. Signing out must always succeed locally: a person on a train asking
    /// to be signed out is entitled to be signed out, and a server that cannot be reached
    /// to be told will expire the session on its own.
    func signOut() async
}
