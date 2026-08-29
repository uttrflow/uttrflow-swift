public import Foundation

/// The one place this module opens a socket.
///
/// Small enough that reading it is the review, which is the deal ``BackendTransport``
/// makes: every decision worth getting wrong is in the request that was handed here, and
/// all this does is put it on the wire and hand back what came off.
public struct URLSessionTransport: BackendTransport {
    private let session: URLSession

    /// - Parameter session: The session to use. The default is ephemeral **on purpose**:
    ///   a disk cache would write copies of the profile — which names the person and their
    ///   plan — into a cache directory nothing else in this app knows about or clears, and
    ///   a cookie store would keep state for a service that authenticates with a bearer
    ///   token and sets no cookies.
    public init(session: URLSession = URLSessionTransport.defaultSession()) {
        self.session = session
    }

    public static func defaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral

        // No cache at all, and this one is load-bearing rather than tidy.
        //
        // `URLSession` does HTTP caching itself. Given a cached response it will revalidate
        // on its own, and when the server answers `304` it *does not tell the caller*: it
        // returns the cached body as a `200`, which is correct behaviour and exactly wrong
        // here. This app sends its own `If-None-Match` and needs to see the `304`, because
        // that answer is what tells it the cached profile is current. With a cache in the
        // way every launch looked like a change: the profile was rewritten and an
        // entitlement re-signed, for ever, silently. It was found by the one test that runs
        // against a real backend, and by nothing else.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        // Long enough to survive a slow hotel connection, short enough that a first-run
        // sign-in on a dead network fails while the user is still watching.
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    public func perform(_ request: BackendRequest) async throws(BackendUnreachable) -> BackendResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                // Not reachable over HTTP(S), and the caller's only sane reading of a
                // response with no status is that the request did not happen.
                throw BackendUnreachable(url: request.url, reason: "the response was not HTTP")
            }
            var headers: [String: String] = [:]
            for (name, value) in http.allHeaderFields {
                if let name = name as? String, let value = value as? String {
                    headers[name] = value
                }
            }
            return BackendResponse(status: http.statusCode, headers: headers, body: data)
        } catch let unreachable as BackendUnreachable {
            throw unreachable
        } catch {
            // Every URLSession failure is "the request did not happen": no network, DNS,
            // TLS, timeout, cancellation. None of them is the server saying no, and the
            // difference decides whether this Mac keeps working offline.
            throw BackendUnreachable(url: request.url, reason: error.localizedDescription)
        }
    }
}
