public import Foundation

/// The corpus service as request-building and answer-reading; the injected ``HTTPTransport`` owns the socket.
public struct BackendCorpusClient: CorpusCatalogue, CorpusUploading {
    /// Where the corpus service is; no default, so a forgotten flag cannot point at production.
    private let baseURL: URL
    /// The operator token, sent to the backend and never to a signed URL, whose signature is its permission.
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
        // Refused rather than followed: a placeholder answers 501, and a thousand of those read as bad audio.
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
        // No bearer token or `Content-Length`: the signature is the permission and the transport sets length.
        _ = try await send(
            .init(method: .put, url: signed, headers: ["Content-Type": "audio/wav"], body: audio))
    }

    // MARK: Talking

    /// The body the registration endpoint takes; the row's `id` is the backend's to issue.
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
        // `appending(path:)` keeps a prefix-mounted base whole; `URL(string:relativeTo:)` would drop it.
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url = url.appending(queryItems: query) }
        return url
    }

    private func queryItems(for query: CorpusQuery) -> [URLQueryItem] {
        // Assembled in a fixed order so identical queries produce one cache key and one log line.
        var items: [URLQueryItem] = []
        if let language = query.language { items.append(.init(name: "language", value: language)) }
        if let stress = query.stress { items.append(.init(name: "stress", value: stress)) }
        if let heldOut = query.heldOut { items.append(.init(name: "heldOut", value: "\(heldOut)")) }
        if let limit = query.limit { items.append(.init(name: "limit", value: "\(limit)")) }
        if let offset = query.offset { items.append(.init(name: "offset", value: "\(offset)")) }
        return items
    }

    /// Performs a request and turns anything but a 2xx into a ``CorpusError`` naming `slug`.
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

    /// Turns a status and body into a ``CorpusError``; a 404 without our `error` field means no endpoint.
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
