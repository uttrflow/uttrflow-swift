import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowSpeech

/// Writes the tokenizer a real install leaves beside the weights, one byte per file.
private func writeTokenizer(into destination: URL) throws {
    for name in TokenizerAssets.fileNames {
        try Data([1]).write(to: destination.appending(path: name))
    }
}

/// The bytes ``writeTokenizer(into:)`` adds to a model's directory.
private let tokenizerBytes = Int64(TokenizerAssets.fileNames.count)

/// Runs against a real temporary directory, since the store's whole job is filesystem behaviour.
@Suite("FileSystemSpeechModelStore")
struct FileSystemSpeechModelStoreTests {
    private struct Sandbox: ~Copyable {
        let root: URL
        init() {
            root = URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "uttrflow-store-\(UUID().uuidString)")
        }
        deinit { try? FileManager.default.removeItem(at: root) }
    }

    /// A downloader that writes a plausible install with progress, and a one-byte-per-file tokenizer.
    private func writingDownloader(
        fileCount: Int = 2, bytesEach: Int = 16, progressSteps: [Double] = [0.5]
    ) -> FileSystemSpeechModelStore.Downloader {
        { _, component, destination, onProgress in
            switch component {
            case .weights:
                for step in progressSteps { onProgress(step) }
                for index in 0..<fileCount {
                    try Data(repeating: 7, count: bytesEach).write(
                        to: destination.appending(path: "part-\(index).bin")
                    )
                }
            case .tokenizer:
                try writeTokenizer(into: destination)
            }
        }
    }

    @Test("puts each model in its own directory under the root")
    func location() {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())
        #expect(store.location(of: .base).lastPathComponent == SpeechModel.base.variant)
        #expect(store.location(of: .base).deletingLastPathComponent().path == sandbox.root.path)
    }

    @Test("reports nothing installed to begin with")
    func emptyStore() {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())

        #expect(!store.isInstalled(.base))
        #expect(store.installedModels().isEmpty)
        #expect(store.bytesOnDisk(.base) == nil)
    }

    @Test("installs a model and reports it afterwards")
    func install() async throws {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())

        let url = try await store.install(.base) { _ in }

        #expect(url == store.location(of: .base))
        #expect(store.isInstalled(.base))
        #expect(store.installedModels() == [.base])
        #expect(store.bytesOnDisk(.base) == 32 + tokenizerBytes)
    }

    @Test("reports progress and always finishes at one")
    func progress() async throws {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(
            root: sandbox.root, download: writingDownloader(progressSteps: [0.25, 0.75])
        )
        let seen = Mutex<[Double]>([])

        try await store.install(.base) { fraction in seen.withLock { $0.append(fraction) } }

        #expect(seen.withLock { $0 } == [0.25, 0.75, 1.0])
    }

    @Test("does not download again when the model is already there")
    func installIsIdempotent() async throws {
        let sandbox = Sandbox()
        let fetched = Mutex<[ModelComponent]>([])
        let inner = writingDownloader()
        let store = FileSystemSpeechModelStore(root: sandbox.root) {
            model, component, destination, progress in
            fetched.withLock { $0.append(component) }
            try await inner(model, component, destination, progress)
        }

        try await store.install(.base) { _ in }
        #expect(fetched.withLock { $0 } == [.weights, .tokenizer])

        try await store.install(.base) { _ in }
        #expect(
            fetched.withLock { $0 } == [.weights, .tokenizer],
            "a complete install must fetch nothing at all")
    }

    /// A weights-only install reads as incomplete and is repaired without a second 600 MB download.
    @Test("tops up a tokenizer-less install without fetching the weights again")
    func repairsAnInstallMissingItsTokenizer() async throws {
        let sandbox = Sandbox()
        let fetched = Mutex<[ModelComponent]>([])
        let inner = writingDownloader()
        let store = FileSystemSpeechModelStore(root: sandbox.root) {
            model, component, destination, progress in
            fetched.withLock { $0.append(component) }
            try await inner(model, component, destination, progress)
        }
        try await store.install(.base) { _ in }
        TokenizerAssets.remove(from: store.location(of: .base))
        fetched.withLock { $0.removeAll() }

        #expect(!store.isInstalled(.base), "weights without a tokenizer cannot transcribe")
        #expect(store.installedModels().isEmpty)

        try await store.install(.base) { _ in }

        #expect(fetched.withLock { $0 } == [.tokenizer], "the weights were already there")
        #expect(store.isInstalled(.base))
    }

    /// Weights already waited for survive a failed tokenizer fetch, and what is left is still not installed.
    @Test("keeps the weights when only the tokenizer fetch fails")
    func failedTokenizerFetchKeepsTheWeights() async throws {
        struct Boom: Error {}
        let sandbox = Sandbox()
        let inner = writingDownloader()
        let store = FileSystemSpeechModelStore(root: sandbox.root) {
            model, component, destination, progress in
            guard component == .tokenizer else {
                return try await inner(model, component, destination, progress)
            }
            // Half a tokenizer, then a dropped connection.
            try Data([1]).write(to: destination.appending(path: TokenizerAssets.fileNames[0]))
            throw Boom()
        }

        await #expect(throws: SpeechEngineError.self) { try await store.install(.base) { _ in } }

        let folder = store.location(of: .base)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "part-0.bin").path))
        #expect(!TokenizerAssets.arePresent(in: folder), "half a tokenizer is not a tokenizer")
        #expect(!store.isInstalled(.base))
    }

    /// A download that reports success and produces nothing is caught now, not a launch later.
    @Test("rejects a tokenizer fetch that produced nothing")
    func silentlyEmptyTokenizerFetchRejected() async {
        let sandbox = Sandbox()
        let inner = writingDownloader()
        let store = FileSystemSpeechModelStore(root: sandbox.root) {
            model, component, destination, progress in
            guard component == .tokenizer else {
                return try await inner(model, component, destination, progress)
            }
        }

        await #expect(throws: SpeechEngineError.self) { try await store.install(.base) { _ in } }
        #expect(!store.isInstalled(.base))
    }

    @Test("still reports complete when asked to install what is already installed")
    func idempotentInstallReportsComplete() async throws {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())
        try await store.install(.base) { _ in }

        let seen = Mutex<[Double]>([])
        try await store.install(.base) { fraction in seen.withLock { $0.append(fraction) } }
        #expect(seen.withLock { $0 } == [1.0])
    }

    /// A half-written directory would be mistaken for a working model next launch.
    @Test("leaves nothing behind when the download fails")
    func failedDownloadCleansUp() async {
        struct Boom: Error {}
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root) { _, _, destination, _ in
            try Data([1, 2, 3]).write(to: destination.appending(path: "partial.bin"))
            throw Boom()
        }

        await #expect(throws: SpeechEngineError.self) { try await store.install(.base) { _ in } }
        #expect(!store.isInstalled(.base))
        #expect(!FileManager.default.fileExists(atPath: store.location(of: .base).path))
    }

    /// An empty directory is what a cancelled download leaves.
    @Test("rejects a download that produced no files")
    func emptyDownloadRejected() async {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root) { _, _, _, _ in }

        await #expect(throws: SpeechEngineError.self) { try await store.install(.base) { _ in } }
        #expect(!store.isInstalled(.base))
    }

    @Test("removes an installed model")
    func remove() async throws {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())
        try await store.install(.base) { _ in }

        try store.remove(.base)

        #expect(!store.isInstalled(.base))
        #expect(store.installedModels().isEmpty)
    }

    @Test("does nothing when asked to remove what is not installed")
    func removeMissingIsSafe() {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())
        #expect(throws: Never.self) { try store.remove(.base) }
    }

    @Test("lists installed models in catalogue order")
    func installedOrder() async throws {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())

        try await store.install(.largeV3Turbo) { _ in }
        try await store.install(.base) { _ in }

        #expect(store.installedModels() == [.base, .largeV3Turbo])
    }

    @Test("puts models somewhere durable by default, not in a cache")
    func defaultRoot() {
        let root = FileSystemSpeechModelStore.defaultRoot()
        #expect(root.path.contains("Uttrflow"))
        #expect(root.lastPathComponent == "Models")
    }
}

/// Model repositories nest their output; the store promises files directly in the model's directory.
@Suite("Hoisting a nested download")
struct HoistTests {
    private struct Sandbox: ~Copyable {
        let root: URL
        init() {
            root = URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "uttrflow-hoist-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: root) }
    }

    private func write(_ url: URL, _ contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    @Test("lifts files out of the wrapper the download created, and removes it")
    func hoists() throws {
        let sandbox = Sandbox()
        let nested = sandbox.root.appending(path: "models/argmaxinc/whisperkit-coreml/variant")
        try write(nested.appending(path: "MelSpectrogram.mlmodelc/coremldata.bin"), "mel")
        try write(nested.appending(path: "config.json"), "{}")

        try FileSystemSpeechModelStore.hoist(contentsOf: nested, into: sandbox.root)

        let fileManager = FileManager.default
        #expect(fileManager.fileExists(atPath: sandbox.root.appending(path: "config.json").path))
        #expect(
            fileManager.fileExists(
                atPath: sandbox.root.appending(path: "MelSpectrogram.mlmodelc/coremldata.bin").path
            ))
        #expect(!fileManager.fileExists(atPath: sandbox.root.appending(path: "models").path))
    }

    @Test("does nothing when the download was not nested")
    func flatDownloadIsUntouched() throws {
        let sandbox = Sandbox()
        try write(sandbox.root.appending(path: "config.json"), "{}")

        try FileSystemSpeechModelStore.hoist(contentsOf: sandbox.root, into: sandbox.root)

        #expect(FileManager.default.fileExists(atPath: sandbox.root.appending(path: "config.json").path))
    }

    @Test("replaces a file already sitting at the destination")
    func overwritesExisting() throws {
        let sandbox = Sandbox()
        try write(sandbox.root.appending(path: "config.json"), "old")
        let nested = sandbox.root.appending(path: "models/variant")
        try write(nested.appending(path: "config.json"), "new")

        try FileSystemSpeechModelStore.hoist(contentsOf: nested, into: sandbox.root)

        let contents = try String(contentsOf: sandbox.root.appending(path: "config.json"), encoding: .utf8)
        #expect(contents == "new")
    }
}

/// Whether a folder holds a tokenizer is answered once, for the store and the recogniser alike.
@Suite("Tokenizer files beside the weights")
struct TokenizerAssetsTests {
    private struct Sandbox: ~Copyable {
        let root: URL
        init() {
            root = URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "uttrflow-tokenizer-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: root) }
    }

    /// WhisperKit needs the vocabulary to find a folder worth reading and the configuration to build from it.
    @Test("asks for the vocabulary and the tokeniser configuration")
    func namesBothFiles() {
        #expect(TokenizerAssets.fileNames.contains("tokenizer.json"))
        #expect(TokenizerAssets.fileNames.contains("tokenizer_config.json"))
    }

    @Test("finds a complete tokenizer")
    func complete() throws {
        let sandbox = Sandbox()
        try writeTokenizer(into: sandbox.root)

        #expect(TokenizerAssets.arePresent(in: sandbox.root))
    }

    @Test("reports nothing in an empty folder, or one that is not there at all")
    func absent() {
        let sandbox = Sandbox()
        #expect(!TokenizerAssets.arePresent(in: sandbox.root))
        #expect(!TokenizerAssets.arePresent(in: sandbox.root.appending(path: "nowhere")))
    }

    /// Half a tokenizer called present would send the recogniser to the network while decoding.
    @Test(
        "refuses a folder holding only one of the two files",
        arguments: TokenizerAssets.fileNames)
    func partial(name: String) throws {
        let sandbox = Sandbox()
        try Data([1]).write(to: sandbox.root.appending(path: name))

        #expect(!TokenizerAssets.arePresent(in: sandbox.root))
    }

    @Test("takes the tokenizer away again, and leaves the weights alone")
    func removal() throws {
        let sandbox = Sandbox()
        try writeTokenizer(into: sandbox.root)
        let weights = sandbox.root.appending(path: "AudioEncoder.mlmodelc")
        try Data([7]).write(to: weights)

        TokenizerAssets.remove(from: sandbox.root)

        #expect(!TokenizerAssets.arePresent(in: sandbox.root))
        #expect(FileManager.default.fileExists(atPath: weights.path))
    }

    @Test("says nothing when there is no tokenizer to remove")
    func removalIsSafeWhenAbsent() {
        let sandbox = Sandbox()
        TokenizerAssets.remove(from: sandbox.root)
        #expect(!TokenizerAssets.arePresent(in: sandbox.root))
    }
}
