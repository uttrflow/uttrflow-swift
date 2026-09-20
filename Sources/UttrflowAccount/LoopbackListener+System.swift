// The real loopback listener over Network.framework: one port, one browser redirect, then closed.
public import Foundation
import Network
private import Synchronization
public import UttrflowCore

/// Binds an OS-chosen port on `127.0.0.1` only, waits for the callback carrying this attempt's state, and closes.
public actor SystemLoopbackListener: LoopbackListening {
    /// The path the redirect arrives on; fixed, so a stray request to `/` is distinguishable in a log.
    public static let callbackPath = "/callback"

    /// The most connections one attempt accepts; a browser needs two or three.
    static let connectionLimit = 32

    /// The refusal for a wait that ended with no browser having arrived.
    private static let noAnswer = AccountError.providerRefused(description: "that sign-in did not come back")

    /// The bound listener, until closed.
    private var listener: NWListener?
    /// Connections accepted this attempt, cancelled on close.
    private var connections: [NWConnection] = []
    /// How many connections this attempt has accepted, including those refused over the limit.
    private var accepted = 0
    /// The state a callback must carry to be answered as signed in and handed to the waiter.
    private var expectedState: String?
    /// The caller waiting for the callback, if any.
    private var waiting: CheckedContinuation<LoopbackCallback, any Error>?
    /// The callback that arrived, kept in case the wait begins after it.
    private var received: LoopbackCallback?

    /// Binds nothing until asked.
    public init() {}

    /// Binds a port and returns the redirect URI; ``AccountError/serverUnreachable`` when none binds.
    public func bind(expecting state: String) async throws(AccountError) -> URL {
        expectedState = state
        do {
            let parameters = NWParameters.tcp
            // Loopback only, or the port is reachable from the local network.
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)

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
            // No port is not a refusal; the device flow is the way round it.
            throw .serverUnreachable
        }
    }

    /// Waits for the callback carrying the expected state; cancellation throws the no-answer refusal.
    public func awaitCallback() async throws(AccountError) -> LoopbackCallback {
        if let received { return received }

        do {
            return try await withCheckedThrowingContinuation { continuation in
                waiting = continuation
            }
        } catch {
            throw Self.noAnswer
        }
    }

    /// Cancels the listener and every connection, and resumes any waiter with a cancellation.
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

    /// Starts a connection and reads its first request.
    private func accept(_ connection: NWConnection) {
        accepted += 1
        guard accepted <= Self.connectionLimit else {
            connection.cancel()
            return
        }
        connections.append(connection)
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8) else { return }
            Task { await self?.handle(request, on: connection) }
        }
    }

    /// Parses the request, answers it, and hands the callback carrying the expected state to the waiter.
    private func handle(_ request: String, on connection: NWConnection) {
        let callback = Self.parse(request).flatMap { callback in
            Self.answers(callback, expecting: expectedState, received: received) ? callback : nil
        }
        respond(to: connection, signedIn: callback != nil)

        guard let callback, received == nil else { return }
        received = callback
        if let waiting {
            self.waiting = nil
            waiting.resume(returning: callback)
        }
    }

    /// Whether `callback` carries the expected state and is the first such callback, or a repeat of it.
    static func answers(
        _ callback: LoopbackCallback, expecting state: String?, received: LoopbackCallback?
    ) -> Bool {
        guard let state, callback.state == state else { return false }
        return received == nil || received == callback
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

    /// Sends a page saying whether the sign-in worked, then closes the connection.
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

    /// The page the browser shows after the redirect.
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

/// A one-shot latch shared by the state-handler closures, because resuming a continuation twice is a crash.
private final class Resumed: Sendable {
    /// Whether the continuation is spent.
    private let used = Mutex(false)

    /// Whether this is the first call.
    func claim() -> Bool {
        used.withLock { used in
            defer { used = true }
            return !used
        }
    }
}
