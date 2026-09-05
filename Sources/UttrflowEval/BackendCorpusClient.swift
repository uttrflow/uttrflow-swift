public import Foundation

/// The corpus service, as this harness sees it.
///
/// Everything here is request-building and answer-reading — no socket, no session, no
/// retry timer. The one piece that opens a connection is the ``HTTPTransport`` handed
/// in, which lives in the executable. That division is not tidiness: it is what lets
/// every path below, including the ones that only happen when a backend is misconfigured
/// at three in the morning, be exercised by a test with no network.
public struct BackendCorpusClient: CorpusCatalogue, CorpusUploading {
    /// Where the corpus service is. No default: a measurement tool that silently pointed
    /// at production because somebody forgot a flag is worse than one that refuses.
    private let baseURL: URL
    /// The operator token. Sent to the backend and to nothing else — a signed URL
    /// carries its own permission in the signature, and attaching a bearer token to it
    /// would hand the corpus credential to whoever is serving the bucket.
    private let operatorToken: String?
    private let transport: any HTTPTransport

    public init(baseURL: URL, operatorToken: String?, transport: any HTTPTransport) {
        self.baseURL = baseURL
        self.operatorToken = operatorToken
        self.transport = transport
    }

    // MARK: Reading

    public func samples(matching query: CorpusQuery) async throws(CorpusError) -> CorpusPage {
        let url = endpoint("v1/corpus/samples", query: queryItems(for: query))
        return try decode(
            CorpusPage.self, from: try await send(.init(method: .get, url: url, headers: authorised())))
    }

    public func download(_ slug: String) async throws(CorpusError) -> CorpusDownload {
        let url = endpoint("v1/corpus/samples/\(slug)/download")
        let grant = try decode(
            CorpusDownload.self,
            from: try await send(.init(method: .get, url: url, headers: authorised()), about: slug))
        // Refused here rather than followed. A placeholder URL answers 501 with an
        // explanation, and a run that downloaded a thousand of those would report a
        // thousand unreadable recordings instead of one configuration problem.
        guard !grant.isPlaceholder else { throw .storageNotConfigured }
        return grant
    }

    public func audio(at url: String) async throws(CorpusError) -> Data {
        try await send(.init(method: .get, url: try signedURL(url))).body
    }

    // MARK: Writing

    public func register(_ sample: CorpusSample) async throws(CorpusError) -> CorpusUpload {
        let url = endpoint("v1/corpus/samples")
        var headers = authorised()
        headers["Content-Type"] = "application/json"
        let body: Data
        do {
            body = try JSONEncoder().encode(SampleRegistration(sample))
        } catch {
            throw .malformed("could not encode \(sample.slug): \(error)")
        }
        let grant = try decode(
            CorpusUpload.self,
            from: try await send(.init(method: .post, url: url, headers: headers, body: body)))
        guard !grant.isPlaceholder else { throw .storageNotConfigured }
        return grant
    }

    public func upload(_ audio: Data, to upload: CorpusUpload) async throws(CorpusError) {
        let signed = try signedURL(upload.url)
        // No bearer token and no `Content-Length`: the signature is the permission, and
        // the transport sets the length from the body it is given.
        _ = try await send(
            .init(method: .put, url: signed, headers: ["Content-Type": "audio/wav"], body: audio))
    }

    // MARK: Talking

    /// The body the registration endpoint takes.
    ///
    /// Its own type rather than encoding a ``CorpusSample``: the row's `id` is the
    /// backend's to issue, and a client that posted one would be inventing a primary key.
    private struct SampleRegistration: Encodable {
        let slug: String
        let s3Key: String
        let referenceText: String
        let expectedTidiedText: String
        let language: String
        let stresses: [String]
        let durationMs: Int
        let sampleRateHz: Int
        let byteSize: Int?
        let isHeldOut: Bool
        let cohort: String?

        init(_ sample: CorpusSample) {
            slug = sample.slug
            s3Key = sample.s3Key
            referenceText = sample.referenceText
            expectedTidiedText = sample.expectedTidiedText
            language = sample.language
            stresses = sample.stresses
            durationMs = sample.durationMs
            sampleRateHz = sample.sampleRateHz
            byteSize = sample.byteSize
            isHeldOut = sample.isHeldOut
            cohort = sample.cohort
        }
    }

    /// A signed URL as the service wrote it, refused as malformed when it is not one.
    private func signedURL(_ string: String) throws(CorpusError) -> URL {
        guard let url = URL(string: string) else { throw .malformed("not a URL: \(string)") }
        return url
    }

    private func authorised() -> [String: String] {
        operatorToken.map { ["Authorization": "Bearer \($0)"] } ?? [:]
    }

    private func endpoint(_ path: String, query: [URLQueryItem] = []) -> URL {
        // `appending(path:)` on a base with no trailing slash keeps the whole base, which
        // is what a service mounted under a prefix needs. `URL(string:relativeTo:)` would
        // instead throw the last path component away.
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url = url.appending(queryItems: query) }
        return url
    }

    private func queryItems(for query: CorpusQuery) -> [URLQueryItem] {
        // Assembled in a fixed order so two identical queries produce one cache key and
        // one readable line in a log.
        var items: [URLQueryItem] = []
        if let language = query.language { items.append(.init(name: "language", value: language)) }
        if let stress = query.stress { items.append(.init(name: "stress", value: stress)) }
        if let heldOut = query.heldOut { items.append(.init(name: "heldOut", value: "\(heldOut)")) }
        if let limit = query.limit { items.append(.init(name: "limit", value: "\(limit)")) }
        if let offset = query.offset { items.append(.init(name: "offset", value: "\(offset)")) }
        return items
    }

    /// Performs a request and turns anything but a 2xx into a ``CorpusError``.
    ///
    /// - Parameters:
    ///   - request: What to ask for.
    ///   - slug: The sample the request is about, so a 404 can name it. The URL cannot:
    ///     the not-found path ends in `/download`.
    /// - Returns: The service's answer, which is a success.
    /// - Throws: A ``CorpusError`` describing what the operator has to do about it.
    private func send(
        _ request: HTTPRequest, about slug: String? = nil
    ) async throws(CorpusError) -> HTTPResponse {
        let response: HTTPResponse
        do {
            response = try await transport.perform(request)
        } catch {
            throw .unreachable(error.reason)
        }
        guard response.isSuccess else { throw failure(response, request: request, slug: slug) }
        return response
    }

    /// Turns a status and a body into something the operator can act on.
    ///
    /// The backend's own errors carry a machine-readable `error` field, and Fastify's
    /// default 404 does not name one of ours. That is the difference between "this
    /// sample does not exist" and "this backend does not have the endpoint yet", which
    /// are the same status code and completely different problems.
    private func failure(_ response: HTTPResponse, request: HTTPRequest, slug: String?) -> CorpusError {
        let code = errorCode(in: response.body)
        switch response.status {
        case 401, 403: return .notAuthorised
        case 404 where code == "unknown_sample":
            return .unknownSample(slug ?? request.url.lastPathComponent)
        case 404:
            return .endpointMissing("\(request.method.rawValue) \(request.url.path())")
        case 501 where code == "storage_not_configured": return .storageNotConfigured
        default: return .refused(status: response.status, detail: response.text)
        }
    }

    private func errorCode(in body: Data) -> String? {
        struct Envelope: Decodable { let error: String? }
        return try? JSONDecoder().decode(Envelope.self, from: body).error
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type, from response: HTTPResponse
    ) throws(CorpusError) -> Value {
        do {
            return try JSONDecoder().decode(type, from: response.body)
        } catch {
            throw .malformed("\(error)")
        }
    }
}
