// The loopback listener protocol and the callback it delivers.
public import UttrflowCore
public import struct Foundation.URL

/// The address the browser comes back to, and the answer it carries.
public struct LoopbackCallback: Sendable, Equatable {
    /// The single-use authorization code, worthless without the verifier this process kept.
    public let code: String

    /// The value this attempt started with, so an answer meant for another one is recognised and refused.
    public let state: String

    /// Pairs a code with the state that came back beside it.
    public init(code: String, state: String) {
        self.code = code
        self.state = state
    }
}

/// A loopback listener waiting for one browser redirect: RFC 8252's answer for a desktop application.
public protocol LoopbackListening: Sendable {
    /// Binds a port and returns the redirect URI; ``AccountError/serverUnreachable`` when none binds.
    func bind() async throws(AccountError) -> URL

    /// Waits for the first callback and answers the browser with a page; cancelling the task closes the port.
    func awaitCallback() async throws(AccountError) -> LoopbackCallback

    /// Closes the port, whether or not anything arrived.
    func close() async
}
