public import Foundation

/// The corpus audio kept on this Mac, one file per slug, with the catalogue's byte count as the check.
public struct CorpusCache: Sendable {
    /// Beside the recorded corpus, not in the system caches, so a cache clean cannot lose measurement input.
    public static let defaultDirectoryName = ".uttrflow-corpus/audio"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func audioURL(for slug: String) -> URL { directory.appending(path: "\(slug).wav") }

    /// Whether this sample can be read without the network; a size mismatch counts as absent.
    public func holds(_ sample: CorpusSample) -> Bool {
        guard let size = size(of: audioURL(for: sample.slug)) else { return false }
        guard let expected = sample.byteSize else { return size > 0 }
        return size == expected
    }

    /// Writes the audio, or throws `truncated` before writing when the length disagrees with the catalogue.
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

    /// What the cache holds, so a run can say how much of the corpus is already here.
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

/// The corpus as the harness wants it: samples and a local file for each; the one type that skips downloads.
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

    /// A local file holding this sample's audio, downloaded only if it is not already here.
    public func audioURL(for sample: CorpusSample) async throws(CorpusError) -> URL {
        if !cache.holds(sample) {
            let grant = try await catalogue.download(sample.slug)
            try cache.store(try await catalogue.audio(at: grant.url), for: sample)
        }
        return cache.audioURL(for: sample.slug)
    }

    /// Fetches every sample not already here, reporting each, and returns the ones that failed with why.
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
