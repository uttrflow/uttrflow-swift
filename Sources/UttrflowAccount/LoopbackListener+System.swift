public import Foundation
import Network
public import UttrflowCore

/// The real loopback listener: one port, one browser redirect, then closed.
///
/// Small on purpose, because nothing here can be exercised by a test that does not bind a
/// socket. Everything worth deciding — what goes in the URL, which state is expected, what
/// happens when the answer is wrong — is in ``HTTPAuthenticationService``, on the other
/// side of ``LoopbackListening``.
///
/// Three details are load-bearing:
///
/// * The port is `0`, so the operating system chooses. That is what RFC 8252 §7.3 requires
///   a server to permit, and why the redirect cannot be registered in advance.
/// * It binds to `127.0.0.1` and nothing else, so nothing off this machine can reach it.
/// * It answers exactly one request and closes. A listener left open is a port on the
///   user's machine accepting connections for as long as the app runs.
public actor SystemLoopbackListener: LoopbackListening {
    /// The path the redirect arrives on. Any path would do; a fixed one makes a stray
    /// request to `/` distinguishable from the callback in a log.
    public static let callbackPath = "/callback"

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var waiting: CheckedContinuation<LoopbackCallback, any Error>?
    private var received: LoopbackCallback?
    private var failure: (any Error)?

    public init() {}

    public func bind() async throws(AccountError) -> URL {
        do {
            let parameters = NWParameters.tcp
            // Loopback only. Without this the port is reachable from the local network,
            // which is a listening socket on somebody's laptop in a coffee shop.
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
            parameters.allowLocalEndpointReuse = true

            let listener = try NWListener(using: parameters)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] connection in
                Task { await self?.accept(connection) }
            }

            let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
                let resumed = Resumed()
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard let port = listener.port?.rawValue, resumed.claim() else { return }
                        continuation.resume(returning: port)
                    case .failed(let error), .waiting(let error):
                        guard resumed.claim() else { return }
                        continuation.resume(throwing: error)
                    default:
                        break
                    }
                }
                listener.start(queue: .global(qos: .userInitiated))
            }

            guard let url = URL(string: "http://127.0.0.1:\(port)\(Self.callbackPath)") else {
                throw AccountError.serverUnreachable
            }
            return url
        } catch {
            // No port to bind is not a refusal, it is a Mac that cannot finish this flow.
            // The device grant is the way round it.
            throw .serverUnreachable
        }
    }

    public func awaitCallback() async throws(AccountError) -> LoopbackCallback {
        if let received { return received }
        if failure != nil { throw .providerRefused(description: "that sign-in did not come back") }

        do {
            return try await withCheckedThrowingContinuation { continuation in
                waiting = continuation
            }
        } catch {
            throw .providerRefused(description: "that sign-in did not come back")
        }
    }

    public func close() async {
        listener?.cancel()
        listener = nil
        for connection in connections { connection.cancel() }
        connections = []
        if let waiting {
            self.waiting = nil
            waiting.resume(throwing: CancellationError())
        }
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8) else { return }
            Task { await self?.handle(request, on: connection) }
        }
    }

    private func handle(_ request: String, on connection: NWConnection) {
        let callback = Self.parse(request)
        respond(to: connection, signedIn: callback != nil)

        guard let callback else { return }
        received = callback
        if let waiting {
            self.waiting = nil
            waiting.resume(returning: callback)
        }
    }

    /// Pulls the query out of a request line: `GET /callback?code=…&state=… HTTP/1.1`.
    static func parse(_ request: String) -> LoopbackCallback? {
        guard let line = request.split(separator: "\r\n", maxSplits: 1).first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }

        guard let components = URLComponents(string: "http://127.0.0.1\(parts[1])"),
            let items = components.queryItems,
            let code = items.first(where: { $0.name == "code" })?.value,
            let state = items.first(where: { $0.name == "state" })?.value
        else { return nil }
        return LoopbackCallback(code: code, state: state)
    }

    private func respond(to connection: NWConnection, signedIn: Bool) {
        let body = Self.page(signedIn: signedIn)
        let response = """
            HTTP/1.1 \(signedIn ? "200 OK" : "400 Bad Request")\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """
        connection.send(
            content: Data(response.utf8),
            completion: .contentProcessed { _ in connection.cancel() })
    }

    static func page(signedIn: Bool) -> String {
        let heading = signedIn ? "Signed in" : "Sign-in failed"
        let message =
            signedIn
            ? "You can close this window and go back to Uttrflow."
            : "Something went wrong. Go back to Uttrflow and try again."
        return """
            <!doctype html>
            <html lang="en-GB">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Uttrflow — \(heading)</title>
            <style>
              :root { color-scheme: light dark; }
              body { font: 16px/1.6 -apple-system, BlinkMacSystemFont, sans-serif;
                     margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 2rem; }
              main { max-width: 26rem; text-align: center; }
              h1 { font-size: 1.4rem; margin: 0 0 0.5rem; }
              p { margin: 0; opacity: 0.75; }
            </style>
            </head>
            <body><main><h1>\(heading)</h1><p>\(message)</p></main></body>
            </html>
            """
    }
}

/// A one-shot latch, so a continuation cannot be resumed twice.
///
/// `NWListener`'s state handler is called for every transition, and both `.ready` and
/// `.failed` can arrive for one listener. Resuming a continuation twice is a crash, not an
/// error, so the guard is a class the closures share rather than a captured `var`.
private final class Resumed: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
