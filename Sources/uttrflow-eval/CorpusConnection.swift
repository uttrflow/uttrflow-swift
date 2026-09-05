// The corpus service's URL, token and the one URLSession that reaches it.
import ArgumentParser
internal import Foundation
internal import UttrflowEval

/// The only code that opens a network connection for the corpus; every decision lives in `UttrflowEval`.
struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    /// Uses its own configuration, not `.shared`, so a thousand large objects are not cached in memory.
    init(timeout: TimeInterval = 60) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func perform(_ request: HTTPRequest) async throws(HTTPTransportError) -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        urlRequest.httpBody = request.body

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw HTTPTransportError(url: request.url, reason: "the answer was not HTTP")
            }
            return HTTPResponse(status: http.statusCode, body: data)
        } catch let error as HTTPTransportError {
            throw error
        } catch {
            throw HTTPTransportError(url: request.url, reason: error.localizedDescription)
        }
    }
}

/// Where the corpus service is and who this is, shared by every command that talks to it.
struct CorpusConnection: ParsableArguments {
    /// Has no default, so a measurement tool cannot quietly point at production.
    @Option(name: .long, help: "Base URL of the corpus service, e.g. http://127.0.0.1:8787")
    var backend: String?

    /// Read from the environment by default: a token on an argument list ends up in shell history.
    @Option(
        name: .long,
        help: "Operator token. Defaults to $UTTRFLOW_OPERATOR_TOKEN, which is the safer place for it."
    )
    var operatorToken: String?

    @Option(name: .long, help: "Where downloaded corpus audio is kept between runs.")
    var cachePath = CorpusCache.defaultDirectoryName

    var token: String? {
        operatorToken ?? ProcessInfo.processInfo.environment["UTTRFLOW_OPERATOR_TOKEN"]
    }

    /// Builds the client, or exits cleanly naming the missing flag before anything expensive happens.
    func client() throws -> BackendCorpusClient {
        guard let backend, let url = URL(string: backend), url.scheme != nil else {
            throw CleanExit.message(
                "Pass --backend with the corpus service's base URL, e.g. --backend http://127.0.0.1:8787")
        }
        return BackendCorpusClient(baseURL: url, operatorToken: token, transport: URLSessionHTTPTransport())
    }

    func library() throws -> CorpusLibrary {
        CorpusLibrary(
            catalogue: try client(), cache: CorpusCache(directory: URL(fileURLWithPath: cachePath)))
    }
}
