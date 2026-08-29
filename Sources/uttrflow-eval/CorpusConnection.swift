import ArgumentParser
internal import Foundation
internal import UttrflowEval

/// The only code in this repository that opens a network connection for the corpus.
///
/// It is here, in an executable that nothing else links, rather than in `UttrflowEval`,
/// and that placement is the point. `Uttrflow.app` links neither this target nor anything
/// that reaches it, so no build of the product can be made to fetch corpus audio however
/// hard somebody tries. The consequence for this file is that it is excluded from the
/// coverage floor, so it has to be small enough that reading it is a sufficient review —
/// which is why every decision worth making, from the URL to the meaning of a 404, is
/// made in `UttrflowEval` and none of them is made here.
struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    /// A configuration of its own rather than `.shared`: the corpus is a thousand
    /// multi-megabyte objects, and a cache that kept them in memory alongside the copy
    /// already being written to disk would double the cost of a pull for nothing.
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

/// Where the corpus service is, and who this is.
///
/// Shared by every command that talks to it, so the flags cannot drift apart between
/// `pull`, `record --upload` and `transcribe --from-corpus`.
struct CorpusConnection: ParsableArguments {
    /// No default, deliberately. A measurement tool that quietly pointed at production
    /// because somebody forgot a flag would produce numbers nobody could place.
    @Option(name: .long, help: "Base URL of the corpus service, e.g. http://127.0.0.1:8787")
    var backend: String?

    /// Taken from the environment rather than the command line by default: a token on an
    /// argument list is a token in the shell history and in every `ps` on the machine.
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

    /// - Throws: A clean exit naming the flag, when there is no backend to talk to. Said
    ///   before anything expensive happens — and, in `record`, before anybody has spoken.
    func client() throws -> BackendCorpusClient {
        guard let backend, let url = URL(string: backend), url.scheme != nil else {
            throw CleanExit.message(
                "Pass --backend with the corpus service's base URL, e.g. --backend http://127.0.0.1:8787")
        }
        return BackendCorpusClient(baseURL: url, operatorToken: token, transport: URLSessionTransport())
    }

    func library() throws -> CorpusLibrary {
        CorpusLibrary(
            catalogue: try client(), cache: CorpusCache(directory: URL(fileURLWithPath: cachePath)))
    }
}
