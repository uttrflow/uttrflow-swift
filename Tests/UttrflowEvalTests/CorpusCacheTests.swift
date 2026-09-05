// Tests the corpus audio cache against real directories.
import Foundation
import Synchronization
import Testing

@testable import UttrflowEval

/// Tested against real directories, since a fake file system would agree with whatever this code did.
@Suite("Corpus audio kept on this Mac")
struct CorpusCacheTests {
    @Test("holds a sample once it has been stored")
    func storesAndReads() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CorpusCache(directory: directory)
        let sample = makeSample("one", bytes: 3)

        #expect(!cache.holds(sample))
        try cache.store(Data([1, 2, 3]), for: sample)
        #expect(cache.holds(sample))
        #expect(try cache.read("one") == Data([1, 2, 3]))
    }

    /// A half-written WAV the next run treats as complete would corrupt every measurement after it.
    @Test("a short download is refused, and nothing is written")
    func refusesATruncatedDownload() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CorpusCache(directory: directory)
        let sample = makeSample("one", bytes: 10)

        #expect(throws: CorpusError.truncated(slug: "one", expected: 10, received: 2)) {
            try cache.store(Data([1, 2]), for: sample)
        }
        #expect(!cache.holds(sample))
        #expect(!FileManager.default.fileExists(atPath: cache.audioURL(for: "one").path))
    }

    /// The honest response to a truncated download is to fetch it again.
    @Test("a file of the wrong length does not count as cached")
    func wrongLengthIsNotCached() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CorpusCache(directory: directory)
        try cache.store(Data([1, 2, 3]), for: makeSample("one", bytes: 3))
        #expect(!cache.holds(makeSample("one", bytes: 4)))
    }

    /// The catalogue does not always know a sample's size, and then presence is all there is.
    @Test("with no promised size, any non-empty file counts")
    func unmeasuredSamples() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CorpusCache(directory: directory)
        try cache.store(Data([1]), for: makeSample("one", bytes: nil))
        #expect(cache.holds(makeSample("one", bytes: nil)))
        try cache.store(Data(), for: makeSample("empty", bytes: nil))
        #expect(!cache.holds(makeSample("empty", bytes: nil)))
    }

    @Test("says what it cannot read")
    func reportsAMissingFile() {
        let cache = CorpusCache(directory: temporaryDirectory())
        #expect(throws: CorpusError.self) { try cache.read("nothing") }
    }

    @Test("says how much of a set is already here")
    func countsWhatIsHeld() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CorpusCache(directory: directory)
        let samples = [
            makeSample("one", bytes: 3), makeSample("two", bytes: 2), makeSample("three", bytes: 1),
        ]
        try cache.store(Data([1, 2, 3]), for: samples[0])
        try cache.store(Data([1, 2]), for: samples[1])

        let held = cache.held(of: samples)
        #expect(held.cached == 2)
        #expect(held.bytes == 5)
    }

    @Test("refuses to write where it cannot")
    func reportsAnUnwritableDirectory() {
        // A path under a regular file cannot become a directory, the cheapest write failure without root.
        let file = temporaryDirectory().appending(path: "occupied")
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let cache = CorpusCache(directory: file.appending(path: "under"))
        #expect(throws: CorpusError.self) { try cache.store(Data([1]), for: makeSample("one", bytes: 1)) }
    }
}

@Suite("The corpus as the harness wants it")
struct CorpusLibraryTests {
    private func library(_ catalogue: FakeCatalogue, _ directory: URL) -> CorpusLibrary {
        CorpusLibrary(catalogue: catalogue, cache: CorpusCache(directory: directory))
    }

    /// A thousand samples is gigabytes, and downloading them again would cost more than the compute.
    @Test("downloads a sample once and reads it from disk afterwards")
    func downloadsOnce() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sample = makeSample("one", bytes: 3)
        var catalogue = FakeCatalogue(samples: [sample], audio: ["one": Data([1, 2, 3])])
        let subject = library(catalogue, directory)

        let url = try await subject.audioURL(for: sample)
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))

        // With the bytes gone from the catalogue, a second call can only succeed from the cache.
        catalogue.audio = [:]
        let again = try await library(catalogue, directory).audioURL(for: sample)
        #expect(try Data(contentsOf: again) == Data([1, 2, 3]))
    }

    /// A domestic connection loses a few; a loop that stopped at the first would never finish.
    @Test("one failure does not stop the rest, and is named at the end")
    func carriesOnPastAFailure() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let samples = [
            makeSample("one", bytes: 1), makeSample("two", bytes: 1), makeSample("three", bytes: 1),
        ]
        let catalogue = FakeCatalogue(
            samples: samples, audio: ["one": Data([1]), "three": Data([3])])
        let subject = library(catalogue, directory)

        // A mutex, because the progress callback is `@Sendable` and a captured `var` would be a race.
        let progress = Mutex<[String]>([])
        let failures = await subject.fetchAll(samples) { sample, error in
            progress.withLock { $0.append("\(sample.slug):\(error == nil ? "ok" : "failed")") }
        }
        #expect(progress.withLock { $0 } == ["one:ok", "two:failed", "three:ok"])
        #expect(failures.map(\.sample.slug) == ["two"])
        #expect(subject.held(of: samples).cached == 2)
    }

    @Test("a backend with no bucket fails once per sample, with the same reason")
    func placeholderStorage() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let samples = [makeSample("one"), makeSample("two")]
        let catalogue = FakeCatalogue(samples: samples, downloadFails: .storageNotConfigured)
        let failures = await library(catalogue, directory).fetchAll(samples)
        #expect(failures.count == 2)
        #expect(failures.allSatisfy { $0.error == .storageNotConfigured })
    }

    @Test("lists the catalogue through the client, paged")
    func lists() async throws {
        let catalogue = FakeCatalogue(samples: (1...5).map { makeSample("s\($0)") }, pageSize: 2)
        let all = try await library(catalogue, temporaryDirectory()).samples()
        #expect(all.count == 5)
    }
}
