import Foundation
import Testing

@testable import UttrflowEval

/// Tested against the shapes the backend returns, from its route definitions and a running instance.
@Suite("The corpus service, as a client")
struct BackendCorpusClientTests {
    private func base() -> URL { URL(fileURLWithPath: "/") }

    private func client(
        _ transport: StubTransport, token: String? = "operator-token"
    )
        -> BackendCorpusClient
    {
        BackendCorpusClient(
            baseURL: URL(string: "https://corpus.test") ?? base(), operatorToken: token,
            transport: transport)
    }

    private let onePage = """
        {"total":1,"count":1,"samples":[{
          "id":"ddd0","slug":"accent-glaswegian","s3Key":"corpus/en-GB/accent-glaswegian.wav",
          "referenceText":"can we push it back an hour",
          "expectedTidiedText":"Can we push it back an hour?",
          "language":"en-GB","stresses":["accent","punctuation"],
          "durationMs":5100,"sampleRateHz":16000,"byteSize":163200,"isHeldOut":false}]}
        """

    @Test("asks for the catalogue with the operator token and the filters it was given")
    func listsSamples() async throws {
        let transport = StubTransport(status: 200, json: onePage)
        let page = try await client(transport).samples(
            matching: CorpusQuery(
                language: "hi-IN", stress: "proper-nouns", heldOut: true, limit: 500, offset: 0))

        #expect(page.total == 1)
        #expect(page.samples.first?.slug == "accent-glaswegian")
        #expect(page.samples.first?.byteSize == 163_200)
        let request = try #require(transport.requests.first)
        #expect(request.url.path() == "/v1/corpus/samples")
        #expect(request.url.query() == "language=hi-IN&stress=proper-nouns&heldOut=true&limit=500&offset=0")
        #expect(request.headers["Authorization"] == "Bearer operator-token")
    }

    /// A field the catalogue does not have yet must not stop the harness reading it.
    @Test("reads a sample that has no cohort column")
    func toleratesAMissingCohort() async throws {
        let page = try await client(StubTransport(status: 200, json: onePage)).samples(
            matching: CorpusQuery())
        #expect(page.samples.first?.cohort == nil)
    }

    /// The backend caps a page at 500, the failure a thousand samples is most likely to hit.
    @Test("pages until it has the whole catalogue")
    func pagesThroughEverything() async throws {
        let catalogue = FakeCatalogue(samples: (1...5).map { makeSample("sample-\($0)") }, pageSize: 2)
        let all = try await catalogue.allSamples()
        #expect(all.map(\.slug) == ["sample-1", "sample-2", "sample-3", "sample-4", "sample-5"])
    }

    @Test("stops rather than spinning when the catalogue miscounts its own total")
    func survivesABadTotal() async throws {
        struct Liar: CorpusCatalogue {
            func samples(matching query: CorpusQuery) async throws(CorpusError) -> CorpusPage {
                CorpusPage(total: 99, count: 0, samples: [])
            }
            func download(_ slug: String) async throws(CorpusError) -> CorpusDownload {
                throw .unknownSample(slug)
            }
            func audio(at url: String) async throws(CorpusError) -> Data { Data() }
        }
        #expect(try await Liar().allSamples().isEmpty)
    }

    @Test("hands back a signed download URL")
    func download() async throws {
        let transport = StubTransport(
            status: 200,
            json:
                #"{"slug":"one","url":"https://bucket.test/one","expiresInSeconds":900,"isPlaceholder":false}"#
        )
        let grant = try await client(transport).download("one")
        #expect(grant.url == "https://bucket.test/one")
        #expect(transport.requests.first?.url.path() == "/v1/corpus/samples/one/download")
    }

    /// Following a placeholder would report a thousand unreadable recordings instead of one problem.
    @Test("refuses a placeholder URL rather than following it")
    func refusesPlaceholders() async {
        let transport = StubTransport(
            status: 200,
            json:
                #"{"slug":"one","url":"http://x/v1/corpus/unavailable","expiresInSeconds":900,"isPlaceholder":true}"#
        )
        await #expect(throws: CorpusError.storageNotConfigured) {
            try await client(transport).download("one")
        }
    }

    /// The same status code, two different problems, and only the body tells them apart.
    @Test("tells an unknown sample from a backend that has not got the endpoint")
    func distinguishesTheTwoKindsOf404() async {
        let unknown = StubTransport(status: 404, json: #"{"error":"unknown_sample"}"#)
        await #expect(throws: CorpusError.unknownSample("missing")) {
            try await client(unknown).download("missing")
        }

        let noRoute = StubTransport(
            status: 404, json: #"{"error":"not_found","message":"No such endpoint."}"#)
        await #expect(throws: CorpusError.endpointMissing("POST /v1/corpus/samples")) {
            try await client(noRoute).register(makeSample("one"))
        }
    }

    /// The last path component is the closest thing to a name a sample-less 404 has.
    @Test("falls back to the path when a 404 is not about a named sample")
    func unknownSampleWithNoSlug() async {
        let transport = StubTransport(status: 404, json: #"{"error":"unknown_sample"}"#)
        await #expect(throws: CorpusError.unknownSample("samples")) {
            try await client(transport).samples(matching: CorpusQuery())
        }
    }

    @Test("reports an unaccepted token as something the operator can fix")
    func notAuthorised() async {
        let transport = StubTransport(status: 401, json: #"{"error":"operator_only"}"#)
        await #expect(throws: CorpusError.notAuthorised) {
            try await client(transport, token: nil).samples(matching: CorpusQuery())
        }
        #expect(transport.requests.first?.headers["Authorization"] == nil)
    }

    @Test("keeps whatever the service said when it refuses for a reason of its own")
    func refused() async {
        let transport = StubTransport(status: 500, json: "upstream exploded")
        await #expect(throws: CorpusError.refused(status: 500, detail: "upstream exploded")) {
            try await client(transport).samples(matching: CorpusQuery())
        }
    }

    @Test("reports a body it cannot read rather than pretending the corpus is empty")
    func malformed() async {
        let transport = StubTransport(status: 200, json: "{oh dear")
        await #expect(throws: CorpusError.self) {
            try await client(transport).samples(matching: CorpusQuery())
        }
    }

    @Test("a connection that could not be made is not an answer")
    func unreachable() async {
        await #expect(throws: CorpusError.unreachable("offline")) {
            try await client(StubTransport(unreachable: "offline")).samples(matching: CorpusQuery())
        }
    }

    @Test("fetches audio from the signed URL without attaching the operator token")
    func fetchesAudio() async throws {
        let transport = StubTransport([
            StubTransport.bytes(Data([1, 2, 3]), when: { $0.url.host() == "bucket.test" })
        ])
        let data = try await client(transport).audio(at: "https://bucket.test/one.wav")
        #expect(data == Data([1, 2, 3]))
        // The signature is the permission; the corpus credential never goes to whoever serves the bucket.
        #expect(transport.requests.first?.headers.isEmpty == true)
    }

    @Test("says so rather than guessing when a URL is not a URL")
    func rejectsANonURL() async {
        await #expect(throws: CorpusError.self) {
            try await client(StubTransport(status: 200, json: "{}")).audio(at: "")
        }
        await #expect(throws: CorpusError.self) {
            try await client(StubTransport(status: 200, json: "{}")).upload(
                Data(), to: CorpusUpload(slug: "one", url: "", expiresInSeconds: 60))
        }
    }

    // MARK: Uploading

    @Test("registers a sample and then puts the bytes where it was told")
    func registersThenUploads() async throws {
        let transport = StubTransport([
            StubTransport.json(
                #"{"slug":"one","url":"https://bucket.test/put/one","expiresInSeconds":900,"isPlaceholder":false}"#,
                when: { $0.method == .post }),
            StubTransport.json("", when: { $0.method == .put }),
        ])
        let subject = client(transport)
        let upload = try await subject.register(makeSample("one"))
        try await subject.upload(Data([9]), to: upload)

        let post = try #require(transport.requests.first)
        #expect(post.url.path() == "/v1/corpus/samples")
        #expect(post.headers["Content-Type"] == "application/json")
        #expect(post.headers["Authorization"] == "Bearer operator-token")
        // The row's identifier is the backend's to issue.
        let body = try #require(post.body).map { $0 }
        #expect(!String(decoding: body, as: UTF8.self).contains("\"id\""))

        let put = try #require(transport.requests.last)
        #expect(put.method == .put)
        #expect(put.headers["Authorization"] == nil)
        #expect(put.body == Data([9]))
    }

    @Test("refuses to upload into a backend with no bucket")
    func refusesPlaceholderUploads() async {
        let transport = StubTransport(
            status: 200,
            json: #"{"slug":"one","url":"http://x","expiresInSeconds":900,"isPlaceholder":true}"#)
        await #expect(throws: CorpusError.storageNotConfigured) {
            try await client(transport).register(makeSample("one"))
        }
    }
}

@Suite("What a corpus failure means")
struct CorpusErrorTests {
    /// Getting this wrong either abandons a recording a retry would send, or retries a rejection for ever.
    @Test("knows which failures are worth trying again")
    func transience() {
        #expect(CorpusError.unreachable("offline").isTransient)
        #expect(CorpusError.refused(status: 503, detail: "").isTransient)
        #expect(CorpusError.truncated(slug: "one", expected: 4, received: 2).isTransient)
        #expect(!CorpusError.refused(status: 400, detail: "").isTransient)
        #expect(!CorpusError.notAuthorised.isTransient)
        #expect(!CorpusError.endpointMissing("POST /x").isTransient)
        #expect(!CorpusError.unknownSample("one").isTransient)
        #expect(!CorpusError.malformed("x").isTransient)
        #expect(!CorpusError.storageNotConfigured.isTransient)
        #expect(!CorpusError.storeFailed(.couldNotRead(path: "x", reason: "y")).isTransient)
    }

    /// Read by a person at a terminal, so each one has to name what to do next.
    @Test("every failure explains itself")
    func descriptions() {
        let all: [CorpusError] = [
            .unreachable("offline"), .notAuthorised, .unknownSample("one"), .endpointMissing("POST /x"),
            .refused(status: 500, detail: "boom"), .malformed("bad json"), .storageNotConfigured,
            .truncated(slug: "one", expected: 4, received: 2),
            .storeFailed(.couldNotWrite(path: "one.wav", reason: "full")),
        ]
        for error in all { #expect(error.description.count > 10) }
        #expect(CorpusError.notAuthorised.description.contains("UTTRFLOW_OPERATOR_TOKEN"))
        #expect(CorpusError.endpointMissing("POST /x").description.contains("POST /x"))
    }
}

@Suite("HTTP as a value")
struct HTTPTransportTests {
    @Test("only 2xx is success")
    func success() {
        #expect(HTTPResponse(status: 200).isSuccess)
        #expect(HTTPResponse(status: 204).isSuccess)
        #expect(!HTTPResponse(status: 301).isSuccess)
        #expect(!HTTPResponse(status: 404).isSuccess)
    }

    /// A proxy's error page can be a hundred kilobytes of HTML.
    @Test("a body shown to a person is trimmed, and says it was")
    func text() {
        #expect(HTTPResponse(status: 400, body: Data("  oh dear\n".utf8)).text == "oh dear")
        let long = HTTPResponse(status: 400, body: Data(String(repeating: "x", count: 900).utf8)).text
        #expect(long.count == 401)
        #expect(long.hasSuffix("…"))
    }

    @Test("a connection failure names the address it could not reach")
    func transportError() {
        let error = HTTPTransportError(url: URL(fileURLWithPath: "/corpus"), reason: "offline")
        #expect(error.description.contains("offline"))
        #expect(error.description.contains("corpus"))
    }
}
