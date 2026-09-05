// The backend as the rest of the app sees it, and the values a sign-in passes around.
public import UttrflowCore
public import struct Foundation.Data
public import struct Foundation.URL

/// How a sign-in finishes, decided by whether this Mac can bind a port. See `Docs/account-session.md`.
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

/// A sign-in started and not finished; holds nothing secret, so the interface may keep and log it.
public struct SignInChallenge: Sendable, Equatable {
    /// The page the app opens in the user's own browser.
    public let authorisationURL: URL

    /// Names this attempt; public, as it travels through the browser, so it only ties an answer to a sign-in.
    public let state: String

    /// How it will finish, decided when it started rather than guessed at afterwards.
    public let method: SignInMethod

    /// A challenge that finishes in the browser unless told otherwise.
    public init(authorisationURL: URL, state: String, method: SignInMethod = .browser) {
        self.authorisationURL = authorisationURL
        self.state = state
        self.method = method
    }
}

/// What re-reading the profile found; three answers, because unchanged and signed out are opposites.
public enum ProfileRefresh: Sendable, Equatable {
    /// The server confirmed the cached copy is current. Nothing to write.
    case unchanged

    /// A newer copy, to be cached in place of whatever was there.
    case updated(Profile)

    /// The server does not know this session; an instruction, not a failure, obeyed by signing out locally.
    case signedOut

    /// Nothing on this Mac to ask with, so the server was not asked; no reason to drop the cached profile.
    case noCredential
}

/// The backend, as the rest of the app sees it: RFC 8252 sign-in, and the only calls that need a network.
public protocol AuthenticationService: Sendable {
    /// Starts a sign-in; the challenge says whether a browser comes back to a port or a code must be shown.
    func beginSignIn(with provider: SignInProvider) async throws(AccountError) -> SignInChallenge

    /// Waits however long the person takes to sign in, then collects the session and the profile.
    func completeSignIn(_ challenge: SignInChallenge) async throws(AccountError) -> Profile

    /// Re-reads the profile with the cached validator, so an unchanged one costs a header, never a document.
    func currentProfile(ifChangedFrom cached: Profile?) async throws(AccountError) -> ProfileRefresh

    /// Fetches the picture at a path on our own backend, or `nil` for anything short of a broken session.
    func avatar(at path: String) async -> Data?

    /// Forgets the credential locally, then tells the server; never throws, as signing out must work offline.
    func signOut() async
}
