public import Foundation

/// The corpus audio, kept on this Mac.
///
/// A thousand recordings is a few gigabytes. Downloading them again for every run would
/// make an unattended overnight comparison of two engines cost more in transfer than in
/// compute, and would put a network failure between the harness and a number it could
/// have produced offline. So a sample is fetched once and then read from disk for ever.
///
/// The cache is deliberately not clever. One file per slug, named by the slug, with the
/// catalogue's own byte count as the only validity check — because the failure this has
/// to survive is a download cut off half way, and a half-written WAV that the next run
/// treats as complete is the one bug that would quietly corrupt every measurement after
/// it.
public struct CorpusCache: Sendable {
    /// Beside the recorded corpus rather than in the system caches directory: this is
    /// measurement input, and a tool that cleans up caches must not be able to make a
    /// week of results irreproducible.
    public static let defaultDirectoryName = ".uttrflow-corpus/audio"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func audioURL(for slug: String) -> URL { directory.appending(path: "\(slug).wav") }

    /// Whether this sample can be read without the network.
    ///
    /// A file whose size disagrees with the catalogue is treated as absent, not as an
    /// error: the honest response to a truncated download is to fetch it again.
    public func holds(_ sample: CorpusSample) -> Bool {
        guard let size = size(of: audioURL(for: sample.slug)) else { return false }
        guard let expected = sample.byteSize else { return size > 0 }
        return size == expected
    }

    /// - Throws: ``CorpusError/truncated(slug:expected:received:)`` when the bytes are
    ///   not the length the catalogue promised, before anything is written. A short read
    ///   that reached disk would be indistinguishable from a cached sample on the next
    ///   run.
    public func store(_ audio: Data, for sample: CorpusSample) throws(CorpusError) {
        if let expected = sample.byteSize, audio.count != expected {
            throw .truncated(slug: sample.slug, expected: expected, received: audio.count)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try audio.write(to: audioURL(for: sample.slug), options: .atomic)
        } catch {
            throw .storeFailed(.couldNotWrite(path: "\(sample.slug).wav", reason: "\(error)"))
        }
    }

    public func read(_ slug: String) throws(CorpusError) -> Data {
        do {
            return try Data(contentsOf: audioURL(for: slug))
        } catch {
            throw .storeFailed(.couldNotRead(path: "\(slug).wav", reason: "\(error)"))
        }
    }

    /// What the cache is holding, so a run can say how much of the corpus it already has
    /// before deciding whether tonight is a good night to fetch the rest.
    public func held(of samples: [CorpusSample]) -> (cached: Int, bytes: Int) {
        samples.reduce(into: (0, 0)) { total, sample in
            guard holds(sample) else { return }
            total.0 += 1
            total.1 += size(of: audioURL(for: sample.slug)) ?? 0
        }
    }

    private func size(of url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }
}

/// The corpus as the harness wants it: samples, and a local file for each.
///
/// The only type that knows a download can be skipped. Splitting it from
/// ``CorpusCatalogue`` keeps the client a plain description of the API and keeps the
/// caching rule — which is the part that would otherwise be reimplemented slightly
/// differently at each call site — in one place.
public struct CorpusLibrary: Sendable {
    private let catalogue: any CorpusCatalogue
    private let cache: CorpusCache

    public init(catalogue: any CorpusCatalogue, cache: CorpusCache) {
        self.catalogue = catalogue
        self.cache = cache
    }

    public func samples(
        matching query: CorpusQuery = CorpusQuery()
    ) async throws(CorpusError)
        -> [CorpusSample]
    {
        try await catalogue.allSamples(matching: query)
    }

    /// A local file holding this sample's audio, downloading it only if it is not
    /// already here.
    public func audioURL(for sample: CorpusSample) async throws(CorpusError) -> URL {
        if !cache.holds(sample) {
            let grant = try await catalogue.download(sample.slug)
            try cache.store(try await catalogue.audio(at: grant.url), for: sample)
        }
        return cache.audioURL(for: sample.slug)
    }

    /// Brings a whole set of samples onto this Mac, reporting as it goes.
    ///
    /// One failure does not stop the rest. Fetching a thousand samples over a domestic
    /// connection will lose a few, and a loop that gave up on the first would never
    /// finish; the ones that failed are named at the end and picked up next time,
    /// because everything already here is skipped.
    /// - Parameters:
    ///   - samples: What to bring onto this Mac.
    ///   - onProgress: Called after each sample with what happened to it.
    /// - Returns: The samples that could not be fetched, with why.
    public func fetchAll(
        _ samples: [CorpusSample],
        onProgress: (@Sendable (CorpusSample, CorpusError?) -> Void)? = nil
    ) async -> [(sample: CorpusSample, error: CorpusError)] {
        var failures: [(sample: CorpusSample, error: CorpusError)] = []
        for sample in samples {
            do {
                _ = try await audioURL(for: sample)
                onProgress?(sample, nil)
            } catch {
                failures.append((sample, error))
                onProgress?(sample, error)
            }
        }
        return failures
    }

    /// How much of this set is already on disk.
    public func held(of samples: [CorpusSample]) -> (cached: Int, bytes: Int) {
        cache.held(of: samples)
    }
}
