// Stub transport, catalogue and uploader shared by the corpus tests.
import Foundation
import Synchronization

@testable import UttrflowEval

/// A transport that answers from a script and remembers what it is asked, so no test needs the backend.
final class StubTransport: HTTPTransport, Sendable {
    struct Exchange: Sendable {
        let match: @Sendable (HTTPRequest) -> Bool
        let answer: Result<HTTPResponse, HTTPTransportError>
    }

    private let exchanges: [Exchange]
    private let seen = Mutex<[HTTPRequest]>([])

    init(_ exchanges: [Exchange]) {
        self.exchanges = exchanges
    }

    /// The common case: one answer, whatever is asked.
    convenience init(status: Int, json: String) {
        self.init([
            Exchange(
                match: { _ in true }, answer: .success(HTTPResponse(status: status, body: Data(json.utf8))))
        ])
    }

    convenience init(unreachable reason: String) {
        // A file URL, the one form that cannot fail to construct, for a stub whose URL nothing reads.
        self.init([
            Exchange(
                match: { _ in true },
                answer: .failure(
                    HTTPTransportError(url: URL(fileURLWithPath: "/corpus"), reason: reason)))
        ])
    }

    var requests: [HTTPRequest] { seen.withLock { $0 } }

    func perform(_ request: HTTPRequest) async throws(HTTPTransportError) -> HTTPResponse {
        seen.withLock { $0.append(request) }
        guard let exchange = exchanges.first(where: { $0.match(request) }) else {
            return HTTPResponse(status: 404, body: Data(#"{"error":"not_found"}"#.utf8))
        }
        switch exchange.answer {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }

    static func json(
        _ body: String, status: Int = 200, when match: @escaping @Sendable (HTTPRequest) -> Bool
    )
        -> Exchange
    {
        Exchange(match: match, answer: .success(HTTPResponse(status: status, body: Data(body.utf8))))
    }

    static func bytes(_ data: Data, when match: @escaping @Sendable (HTTPRequest) -> Bool) -> Exchange {
        Exchange(match: match, answer: .success(HTTPResponse(status: 200, body: data)))
    }
}

/// A catalogue held in memory, for the parts of the harness that only need samples and bytes to arrive.
struct FakeCatalogue: CorpusCatalogue, Sendable {
    var samples: [CorpusSample] = []
    var audio: [String: Data] = [:]
    var pageSize = 2
    var downloadFails: CorpusError?
    var audioFails: CorpusError?

    func samples(matching query: CorpusQuery) async throws(CorpusError) -> CorpusPage {
        let offset = query.offset ?? 0
        let limit = min(query.limit ?? pageSize, pageSize)
        let page = samples.dropFirst(offset).prefix(limit)
        return CorpusPage(total: samples.count, count: page.count, samples: Array(page))
    }

    func download(_ slug: String) async throws(CorpusError) -> CorpusDownload {
        if let downloadFails { throw downloadFails }
        return CorpusDownload(slug: slug, url: "https://bucket.test/\(slug)", expiresInSeconds: 900)
    }

    func audio(at url: String) async throws(CorpusError) -> Data {
        if let audioFails { throw audioFails }
        let slug = String(url.split(separator: "/").last ?? "")
        guard let data = audio[slug] else { throw .unknownSample(slug) }
        return data
    }
}

/// An uploader that records what it is given and can be told to fail.
final class FakeUploader: CorpusUploading, Sendable {
    private let registerResult: Result<CorpusUpload, CorpusError>?
    private let uploadError: CorpusError?
    private let registered = Mutex<[String: CorpusSample]>([:])
    private let sent = Mutex<[(CorpusSample, Data)]>([])

    init(registerResult: Result<CorpusUpload, CorpusError>? = nil, uploadError: CorpusError? = nil) {
        self.registerResult = registerResult
        self.uploadError = uploadError
    }

    var uploads: [(sample: CorpusSample, audio: Data)] { sent.withLock { $0 } }

    func register(_ sample: CorpusSample) async throws(CorpusError) -> CorpusUpload {
        switch registerResult {
        case .failure(let error): throw error
        case .success(let upload): return upload
        case nil:
            registered.withLock { $0[sample.slug] = sample }
            return CorpusUpload(
                slug: sample.slug, url: "https://bucket.test/put/\(sample.slug)", expiresInSeconds: 900)
        }
    }

    func upload(_ audio: Data, to upload: CorpusUpload) async throws(CorpusError) {
        if let uploadError { throw uploadError }
        guard let sample = registered.withLock({ $0[upload.slug] }) else {
            throw .unknownSample(upload.slug)
        }
        sent.withLock { $0.append((sample, audio)) }
    }
}

func makeSample(
    _ slug: String,
    language: String = "en-GB",
    stresses: [String] = ["punctuation"],
    bytes: Int? = 4,
    reference: String = "the build passed ship it",
    heldOut: Bool = false,
    cohort: String? = nil
) -> CorpusSample {
    CorpusSample(
        id: "id-\(slug)", slug: slug, s3Key: "corpus/\(language)/\(slug).wav",
        referenceText: reference, expectedTidiedText: reference, language: language,
        stresses: stresses, durationMs: 4_000, sampleRateHz: 16_000, byteSize: bytes,
        isHeldOut: heldOut, cohort: cohort)
}

func temporaryDirectory() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "uttrflow-corpus-tests/\(UUID().uuidString)")
}
