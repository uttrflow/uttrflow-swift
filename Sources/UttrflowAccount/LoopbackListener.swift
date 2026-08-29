public import UttrflowCore
public import struct Foundation.URL

/// The address the browser comes back to, and the answer it carries.
public struct LoopbackCallback: Sendable, Equatable {
    /// The single-use authorization code, worthless without the verifier this process kept.
    public let code: String

    /// The value this attempt was started with, so an answer meant for a different one can
    /// be recognised and refused.
    public let state: String

    public init(code: String, state: String) {
        self.code = code
        self.state = state
    }
}

/// A listener on the loopback interface, waiting for one browser redirect.
///
/// This is the whole of RFC 8252's answer for a desktop application: the app binds a port
/// the operating system chooses, the browser is sent to the authorization server, and the
/// server redirects back to `http://127.0.0.1:<port>/callback`. No URL scheme is
/// registered with the operating system, so nothing else on the machine can claim the
/// redirect, and the flow is identical on macOS, Windows and Linux.
///
/// A protocol because binding a socket is the one part of sign-in a test cannot exercise,
/// and everything interesting — what is sent, what comes back, what is refused — is on
/// this side of it.
public protocol LoopbackListening: Sendable {
    /// Binds a port and returns the redirect URI to hand to the authorization server.
    ///
    /// - Throws: ``AccountError/serverUnreachable`` when no port can be bound, which is
    ///   the honest reading: this Mac cannot complete a sign-in that needs one, and the
    ///   device flow is the way round it.
    func bind() async throws(AccountError) -> URL

    /// Waits for the browser, and answers it with a page saying it can be closed.
    ///
    /// Returns once, for the first callback that arrives. Cancelling the surrounding task
    /// stops the wait and closes the port.
    func awaitCallback() async throws(AccountError) -> LoopbackCallback

    /// Closes the port, whether or not anything arrived.
    func close() async
}
