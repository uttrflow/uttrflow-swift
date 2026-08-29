public import Foundation

/// What can go wrong talking to the corpus service.
///
/// Split by what the operator has to do about it, not by where in the stack it happened.
/// A run against a thousand samples will hit several of these in one sitting, and the
/// only useful question at that point is which ones are worth trying again.
public enum CorpusError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The backend or the bucket could not be reached at all.
    case unreachable(String)
    /// The operator token was missing, wrong, or not accepted.
    case notAuthorised
    /// No sample by that name.
    case unknownSample(String)
    /// The endpoint this client needs does not exist on the backend it is talking to.
    ///
    /// Its own case because it is the one failure a retry cannot fix and the operator
    /// can: the corpus service is behind the client, and the message says which route
    /// is missing rather than leaving somebody to read a 404 out of a log.
    case endpointMissing(String)
    /// The backend answered, and said no.
    case refused(status: Int, detail: String)
    /// The backend answered with something this client cannot read.
    case malformed(String)
    /// The backend has no bucket configured, so its URLs are placeholders.
    case storageNotConfigured
    /// The bytes arrived and are not the bytes that were promised.
    case truncated(slug: String, expected: Int, received: Int)
    /// A local file could not be read or written.
    case storeFailed(EvaluationStoreError)

    public var description: String {
        switch self {
        case .unreachable(let reason): "could not reach the corpus service: \(reason)"
        case .notAuthorised: "the operator token was not accepted — set UTTRFLOW_OPERATOR_TOKEN"
        case .unknownSample(let slug): "no sample called '\(slug)'"
        case .endpointMissing(let route): "this backend has no \(route) — it needs updating"
        case .refused(let status, let detail): "the corpus service answered \(status): \(detail)"
        case .malformed(let reason): "could not read the corpus service's answer: \(reason)"
        case .storageNotConfigured:
            "the backend has no corpus bucket configured, so its URLs are placeholders "
                + "— set CORPUS_BUCKET and AWS_REGION there"
        case .truncated(let slug, let expected, let received):
            "\(slug) came back as \(received) bytes, not the \(expected) the catalogue promises"
        case .storeFailed(let error): "\(error)"
        }
    }

    /// Whether trying again could plausibly work.
    ///
    /// The distinction the upload outbox is built on: a take held back by a flaky
    /// connection should be retried on the next sitting, and a take the backend has
    /// refused outright should stop asking and start telling somebody.
    public var isTransient: Bool {
        switch self {
        case .unreachable, .truncated: true
        // 5xx is the server having a bad minute; 4xx is this client being wrong.
        case .refused(let status, _): status >= 500
        case .notAuthorised, .unknownSample, .endpointMissing, .malformed, .storageNotConfigured,
            .storeFailed:
            false
        }
    }
}

/// Reading the corpus catalogue.
///
/// Every method a test can satisfy with a dictionary. The corpus is a thousand
/// recordings in a private bucket, so a suite that needed the real one would be a suite
/// that only runs for whoever holds the credentials.
public protocol CorpusCatalogue: Sendable {
    /// One page. Callers who want the corpus want ``allSamples(matching:)``.
    func samples(matching query: CorpusQuery) async throws(CorpusError) -> CorpusPage
    /// Permission to read one sample's audio.
    func download(_ slug: String) async throws(CorpusError) -> CorpusDownload
    /// The bytes behind a signed URL.
    func audio(at url: String) async throws(CorpusError) -> Data
}

extension CorpusCatalogue {
    /// Every sample matching the query, paged.
    ///
    /// Written once, here, rather than at each call site. The backend caps a page at 500
    /// and defaults to 100, so a caller who forgets to page against a thousand samples
    /// gets a tenth of the corpus and a number that looks entirely plausible — which is
    /// the worst failure a measurement tool has.
    public func allSamples(
        matching query: CorpusQuery = CorpusQuery()
    ) async throws(CorpusError)
        -> [CorpusSample]
    {
        var collected: [CorpusSample] = []
        var page = query
        page.limit = query.limit ?? CorpusQuery.maximumPageSize
        page.offset = query.offset ?? 0

        while true {
            let batch = try await samples(matching: page)
            collected.append(contentsOf: batch.samples)
            // Stops on an empty page as well as on a full count, so a backend that
            // miscounts cannot spin this loop for ever.
            guard batch.samples.count > 0, collected.count < batch.total else { return collected }
            page.offset = (page.offset ?? 0) + batch.samples.count
        }
    }
}

/// Putting a recording into the corpus.
///
/// Separate from ``CorpusCatalogue`` because the two have different audiences: every
/// harness run reads, and only a recording session writes. A read-only fake is then the
/// ordinary case in tests rather than a stub with three methods that trap.
public protocol CorpusUploading: Sendable {
    /// Registers the sample and returns where to put the bytes.
    ///
    /// Idempotent by slug — the backend upserts — so a retry after a failed transfer
    /// re-registers rather than duplicating.
    func register(_ sample: CorpusSample) async throws(CorpusError) -> CorpusUpload
    /// Puts the audio at the signed URL the registration returned.
    func upload(_ audio: Data, to upload: CorpusUpload) async throws(CorpusError)
}

/// Permission to write one object for a short while.
public struct CorpusUpload: Sendable, Equatable, Codable {
    public let slug: String
    public let url: String
    public let expiresInSeconds: Int
    public let isPlaceholder: Bool

    public init(slug: String, url: String, expiresInSeconds: Int, isPlaceholder: Bool = false) {
        self.slug = slug
        self.url = url
        self.expiresInSeconds = expiresInSeconds
        self.isPlaceholder = isPlaceholder
    }
}
