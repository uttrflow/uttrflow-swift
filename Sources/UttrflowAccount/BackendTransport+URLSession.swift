public import Foundation

/// The one place this module opens a socket; it puts the request on the wire and hands back what came off.
public struct URLSessionTransport: BackendTransport {
    /// The session every request goes through.
    private let session: URLSession

    /// `session` defaults to an ephemeral one, so no disk cache or cookie store holds a copy of the profile.
    public init(session: URLSession = URLSessionTransport.defaultSession()) {
        self.session = session
    }

    /// An ephemeral session with no cache, so a `304` reaches the caller. See Docs/account-transport.md.
    public static func defaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral

        // No cache, or URLSession hides the 304 behind a cached 200. See Docs/account-transport.md.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        // Survives a slow hotel connection, and fails on a dead network while the user is still watching.
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    /// Performs the request; a `URLSession` failure throws ``BackendUnreachable``, and every answer returns.
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
                // A response with no status is a request that did not happen.
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
            // No network, DNS, TLS, timeout or cancellation: the request did not happen; nobody said no.
            throw BackendUnreachable(url: request.url, reason: error.localizedDescription)
        }
    }
}
