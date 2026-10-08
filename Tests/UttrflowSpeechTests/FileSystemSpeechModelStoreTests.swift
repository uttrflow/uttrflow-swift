// Tests the model store against real directories.
import CryptoKit
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowSpeech

/// A load error that names no cause, as the recogniser's own errors do.
private func loadError(_ text: String) -> NSError {
    NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}

/// A load error wrapping the system's memory refusal, the shape a Core ML error takes.
private let memoryRefusal = NSError(
    domain: "fixture", code: 0,
    userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOMEM))])

/// Writes the tokenizer a real install leaves beside the weights, one byte per file.
private func writeTokenizer(into destination: URL) throws {
    for name in TokenizerAssets.fileNames {
        try Data([1]).write(to: destination.appending(path: name))
    }
}

/// Every file the base model's folder holds, written as the files the store checks for.
private let weightFiles = WeightsAssets.fileNames(of: .base)

/// Writes manifest-sized weight files unless the test requests another size.
private func writeWeights(
    into destination: URL, model: SpeechModel = .base, files: [String]? = nil, bytesEach: Int? = nil
) throws {
    for name in files ?? WeightsAssets.fileNames(of: model) {
        let url = destination.appending(path: name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = bytesEach.map(Int64.init) ?? model.weightFiles[name]?.bytes ?? 1
        FileManager.default.createFile(atPath: url.path, contents: Data([7]))
        try FileHandle(forWritingTo: url).truncate(atOffset: UInt64(bytes))
    }
}

/// The bytes ``writeTokenizer(into:)`` adds to a model's directory.
private let tokenizerBytes = Int64(TokenizerAssets.fileNames.count)

private func fixtureModel(variant: String, revision: String, changed: String) -> SpeechModel {
    SpeechModel(
        variant: variant, downloadBytes: 7, isMultilingual: true,
        weightsRepository: "example/model", weightsRevision: revision,
        weightFiles: [
            "changed.bin": .init(bytes: 3, sha256: changed),
            "unchanged.bin": .init(bytes: 4, sha256: "unchanged"),
        ],
        tokenizerRepository: "example/tokenizer", tokenizerRevision: "tokenizer",
        tokenizerDigests: [:])
}

/// A model whose pins are the real digests of `"same"` and `"new"`, so verification can pass.
private func verifiableModel() -> SpeechModel {
    SpeechModel(
        variant: "verifiable-fixture", downloadBytes: 7, isMultilingual: true,
        weightsRepository: "example/model", weightsRevision: "pinned",
        weightFiles: [
            "changed.bin": .init(bytes: 3, sha256: hexDigest(SHA256.hash(data: Data("new".utf8)))),
            "unchanged.bin": .init(bytes: 4, sha256: hexDigest(SHA256.hash(data: Data("same".utf8)))),
        ],
        tokenizerRepository: "example/tokenizer", tokenizerRevision: "tokenizer",
        tokenizerDigests: [:])
}

/// Writes the files of ``verifiableModel()``, with `changed` as the varying one.
private func writeVerifiable(into folder: URL, changed: String) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("same".utf8).write(to: folder.appending(path: "unchanged.bin"))
    try Data(changed.utf8).write(to: folder.appending(path: "changed.bin"))
}

private func hexDigest(_ digest: SHA256.Digest) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
}

private func isExcludedFromBackup(_ url: URL) throws -> Bool {
    let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
    return values.isExcludedFromBackup == true
}

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
        bytesEach: Int? = nil, progressSteps: [Double] = [0.5]
    ) -> FileSystemSpeechModelStore.Downloader {
        { model, component, destination, onProgress in
            switch component {
            case .weights:
                for step in progressSteps { onProgress(step) }
                try writeWeights(
                    into: destination, model: model, bytesEach: bytesEach)
            case .tokenizer:
                try writeTokenizer(into: destination)
            }
        }
    }

    @Test("totals no file sizes as zero")
    func totalOfNoFileSizes() {
        #expect(FileSystemSpeechModelStore.total(of: []) == 0)
    }

    @Test("totals ordinary file sizes")
    func totalOfOrdinaryFileSizes() {
        #expect(FileSystemSpeechModelStore.total(of: [17, 25, 8]) == 50)
    }

    @Test("treats negative file sizes as zero")
    func totalIgnoresNegativeFileSizes() {
        #expect(FileSystemSpeechModelStore.total(of: [-9, 12]) == 12)
    }

    @Test("saturates file size totals at Int64.max")
    func totalOfOverflowingFileSizes() {
        #expect(FileSystemSpeechModelStore.total(of: [Int.max, 1]) == Int64.max)
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
        #expect(
            store.bytesOnDisk(.base)
                == SpeechModel.base.weightFiles.values.reduce(tokenizerBytes) { $0 + $1.bytes }
                + Int64(SpeechModel.base.weightsRevision.utf8.count))
    }

    @Test("installed models are kept out of backups")
    func installedModelsAreExcludedFromBackup() async throws {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())

        let url = try await store.install(.base) { _ in }
        let tokenizer = url.appending(path: TokenizerAssets.fileNames[0])

        #expect(try isExcludedFromBackup(sandbox.root))
        #expect(try isExcludedFromBackup(url))
        #expect(try isExcludedFromBackup(tokenizer))
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

    @Test("a pinned revision change refreshes weights and preserves unchanged files through staging")
    func revisionBumpRefreshesWeights() async throws {
        let sandbox = Sandbox()
        let old = fixtureModel(variant: "revision-fixture", revision: "old", changed: "old-hash")
        let new = fixtureModel(variant: "revision-fixture", revision: "new", changed: "new-hash")
        let store = FileSystemSpeechModelStore(root: sandbox.root) { model, component, destination, _ in
            switch component {
            case .weights:
                if model.weightsRevision == "old" {
                    try Data("same".utf8).write(to: destination.appending(path: "unchanged.bin"))
                    try Data("old".utf8).write(to: destination.appending(path: "changed.bin"))
                } else {
                    #expect(
                        FileManager.default.fileExists(
                            atPath: destination.appending(path: "unchanged.bin").path))
                    try Data("new".utf8).write(to: destination.appending(path: "changed.bin"))
                }
            case .tokenizer:
                try writeTokenizer(into: destination)
            }
        }

        try await store.install(old) { _ in }
        #expect(store.isInstalled(old))
        #expect(!store.isInstalled(new))

        try await store.install(new) { _ in }

        #expect(store.isInstalled(new))
        #expect(
            try Data(contentsOf: store.location(of: new).appending(path: "unchanged.bin"))
                == Data("same".utf8))
        #expect(
            try Data(contentsOf: store.location(of: new).appending(path: "changed.bin")) == Data("new".utf8))
    }

    @Test("a weight file with the wrong pinned byte count is not installed")
    func wrongWeightSizeIsNotInstalled() throws {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())
        let folder = store.location(of: .base)
        try writeWeights(into: folder)
        try writeTokenizer(into: folder)
        try Data(SpeechModel.base.weightsRevision.utf8).write(
            to: folder.appending(path: WeightsAssets.revisionFileName))
        try Data([1]).write(to: folder.appending(path: weightFiles[3]))

        #expect(WeightsAssets.missing(for: .base, in: folder).contains(weightFiles[3]))
        #expect(!store.isInstalled(.base))
    }

    @Test("weights without a revision record that hash to the pin are adopted in place without a download")
    func adoptsAnUnrecordedVerifiedInstall() async throws {
        let sandbox = Sandbox()
        let model = verifiableModel()
        let fetched = Mutex<[ModelComponent]>([])
        let store = FileSystemSpeechModelStore(root: sandbox.root) { _, component, _, _ in
            fetched.withLock { $0.append(component) }
        }
        let folder = store.location(of: model)
        try writeVerifiable(into: folder, changed: "new")
        try writeTokenizer(into: folder)

        #expect(!store.isInstalled(model))
        #expect(store.whyNotInstalled(model)?.contains("no record of the pinned weights revision") == true)

        try await store.install(model) { _ in }

        #expect(fetched.withLock { $0 }.isEmpty, "a verified install must fetch nothing")
        #expect(store.isInstalled(model))
        #expect(store.whyNotInstalled(model) == nil)
    }

    @Test("weights without a revision record that differ from the pin are fetched, not adopted")
    func refusesAnUnrecordedMismatchedInstall() async throws {
        let sandbox = Sandbox()
        let model = verifiableModel()
        let fetched = Mutex<[ModelComponent]>([])
        let store = FileSystemSpeechModelStore(root: sandbox.root) { _, component, destination, _ in
            fetched.withLock { $0.append(component) }
            try writeVerifiable(into: destination, changed: "new")
        }
        let folder = store.location(of: model)
        try writeVerifiable(into: folder, changed: "old")
        try writeTokenizer(into: folder)

        try await store.install(model) { _ in }

        #expect(fetched.withLock { $0 } == [.weights])
        #expect(try Data(contentsOf: folder.appending(path: "changed.bin")) == Data("new".utf8))
        #expect(store.isInstalled(model))
    }

    @Test("a failed load over intact files keeps its retry")
    func intactFilesKeepTheRetry() async throws {
        let sandbox = Sandbox()
        let model = verifiableModel()
        let store = FileSystemSpeechModelStore(root: sandbox.root) { _, _, _, _ in }
        let folder = store.location(of: model)
        try writeVerifiable(into: folder, changed: "new")
        try writeTokenizer(into: folder)
        try await store.install(model) { _ in }

        let failure = WeightsAssets.loadFailure(of: model, in: folder, error: loadError("boom"))

        #expect(failure == .modelLoadFailed(description: "boom"))
        #expect(store.isInstalled(model))
    }

    @Test("a failed load the system refused memory for keeps its retry and names the class")
    func memoryRefusalKeepsTheRetry() async throws {
        let sandbox = Sandbox()
        let model = verifiableModel()
        let store = FileSystemSpeechModelStore(root: sandbox.root) { _, _, _, _ in }
        let folder = store.location(of: model)
        try writeVerifiable(into: folder, changed: "new")
        try writeTokenizer(into: folder)
        try await store.install(model) { _ in }

        let failure = WeightsAssets.loadFailure(of: model, in: folder, error: memoryRefusal)

        #expect(
            failure == .modelLoadFailed(description: memoryRefusal.localizedDescription, outOfMemory: true))
        #expect(failure.recovery == .retry)
        #expect(SpeechLoadFailureClass(failure) == .outOfMemory)
        #expect(store.isInstalled(model))
    }

    @Test("damaged weights are named as damage even when the load reports a memory refusal")
    func damageOutranksMemoryRefusal() async throws {
        let sandbox = Sandbox()
        let model = verifiableModel()
        let store = FileSystemSpeechModelStore(root: sandbox.root) { _, _, _, _ in }
        let folder = store.location(of: model)
        try writeVerifiable(into: folder, changed: "new")
        try writeTokenizer(into: folder)
        try await store.install(model) { _ in }
        try Data("bad".utf8).write(to: folder.appending(path: "changed.bin"))

        let failure = WeightsAssets.loadFailure(of: model, in: folder, error: memoryRefusal)

        #expect(failure == .modelDamaged(fileCount: 1))
    }

    @Test("a failed load over a truncated weight file or a missing tokenizer reads as not installed")
    func absentFilesReadAsNotInstalled() throws {
        let sandbox = Sandbox()
        let model = verifiableModel()
        let folder = FileSystemSpeechModelStore(root: sandbox.root) { _, _, _, _ in }.location(of: model)
        try writeVerifiable(into: folder, changed: "ne")
        try writeTokenizer(into: folder)
        #expect(WeightsAssets.loadFailure(of: model, in: folder, error: loadError("")) == .modelNotInstalled)

        try writeVerifiable(into: folder, changed: "new")
        TokenizerAssets.remove(from: folder)
        #expect(WeightsAssets.loadFailure(of: model, in: folder, error: loadError("")) == .modelNotInstalled)
    }

    @Test("a failed load over a same-size corrupted file names the damage and the install repairs only it")
    func repairsDamagedWeights() async throws {
        let sandbox = Sandbox()
        let model = verifiableModel()
        let fetched = Mutex<[ModelComponent]>([])
        let store = FileSystemSpeechModelStore(root: sandbox.root) { _, component, destination, _ in
            fetched.withLock { $0.append(component) }
            try writeVerifiable(into: destination, changed: "new")
        }
        let folder = store.location(of: model)
        try writeVerifiable(into: folder, changed: "new")
        try writeTokenizer(into: folder)
        try await store.install(model) { _ in }
        fetched.withLock { $0 = [] }
        try Data("bad".utf8).write(to: folder.appending(path: "changed.bin"))
        #expect(store.isInstalled(model), "a size check alone cannot see the damage")

        let failure = WeightsAssets.loadFailure(of: model, in: folder, error: loadError(""))

        #expect(failure == .modelDamaged(fileCount: 1))
        #expect(failure.recovery == .downloadSpeechModel)
        #expect(!store.isInstalled(model))
        try await store.install(model) { _ in }
        #expect(fetched.withLock { $0 } == [.weights])
        #expect(WeightsAssets.areVerified(for: model, in: folder))
        #expect(store.isInstalled(model))
    }

    @Test("names why a model is not installed")
    func namesWhyNotInstalled() throws {
        let sandbox = Sandbox()
        let model = verifiableModel()
        let store = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())
        let folder = store.location(of: model)

        #expect(store.whyNotInstalled(model)?.contains("has not been downloaded") == true)
        try writeVerifiable(into: folder, changed: "new")
        try FileManager.default.removeItem(at: folder.appending(path: "changed.bin"))
        #expect(store.whyNotInstalled(model)?.contains("1 weight files are missing") == true)
        try writeVerifiable(into: folder, changed: "new")
        try WeightsAssets.recordRevision(of: model, in: folder)
        #expect(store.whyNotInstalled(model)?.contains("tokenizer") == true)
    }

    @Test("a default install removes unused model folders and keeps a model in use")
    func removesSupersededVariantFolders() async throws {
        let sandbox = Sandbox()
        let defaultModel = fixtureModel(
            variant: SpeechModel.default.variant, revision: "default", changed: "default-hash")
        let store = FileSystemSpeechModelStore(root: sandbox.root) { _, component, destination, _ in
            switch component {
            case .weights:
                try Data("new".utf8).write(to: destination.appending(path: "changed.bin"))
                try Data("same".utf8).write(to: destination.appending(path: "unchanged.bin"))
            case .tokenizer:
                try writeTokenizer(into: destination)
            }
        }
        let oldVariant = sandbox.root.appending(path: "removed-variant", directoryHint: .isDirectory)
        let knownVariant = sandbox.root.appending(path: SpeechModel.base.variant, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: oldVariant, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: knownVariant, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: oldVariant.appending(path: "old.bin"))
        var lease = ModelDirectoryUseLease.acquireShared(for: knownVariant)
        #expect(lease != nil)

        try await store.install(defaultModel) { _ in }

        #expect(!FileManager.default.fileExists(atPath: oldVariant.path))
        #expect(FileManager.default.fileExists(atPath: knownVariant.path))

        lease = nil
        try await store.install(defaultModel) { _ in }
        #expect(!FileManager.default.fileExists(atPath: knownVariant.path))
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
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: weightFiles[1]).path))
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

    /// A bundle missing from the directory cannot load, however many other files sit beside it.
    @Test("does not call a model installed when one of its weight files is missing", arguments: weightFiles)
    func missingWeightFileIsNotInstalled(missing: String) throws {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())
        let folder = store.location(of: .base)
        try writeWeights(into: folder, files: weightFiles.filter { $0 != missing })
        try writeTokenizer(into: folder)

        #expect(!store.isInstalled(.base))
        #expect(store.bytesOnDisk(.base) == nil)
    }

    /// A weight file that exists but holds nothing is what a write cut off at its start leaves.
    @Test("does not call a model installed when a weight file is empty")
    func emptyWeightFileIsNotInstalled() throws {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())
        let folder = store.location(of: .base)
        try writeWeights(into: folder)
        try Data().write(to: folder.appending(path: weightFiles[3]))
        try writeTokenizer(into: folder)

        #expect(!store.isInstalled(.base))
    }

    /// A tokenizer file that exists but holds nothing cannot be parsed, so it is not installed.
    @Test("does not call a model installed when a tokenizer file is empty")
    func emptyTokenizerFileIsNotInstalled() throws {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())
        let folder = store.location(of: .base)
        try writeWeights(into: folder)
        try writeTokenizer(into: folder)
        try Data().write(to: folder.appending(path: TokenizerAssets.fileNames[0]))

        #expect(!TokenizerAssets.arePresent(in: folder))
        #expect(!store.isInstalled(.base))
    }

    /// What a download killed partway leaves in the model's directory is repaired by fetching the weights again.
    @Test("fetches the weights again when a killed download left only some of them")
    func repairsAKilledWeightsDownload() async throws {
        let sandbox = Sandbox()
        let fetched = Mutex<[ModelComponent]>([])
        let inner = writingDownloader()
        let store = FileSystemSpeechModelStore(root: sandbox.root) {
            model, component, destination, progress in
            fetched.withLock { $0.append(component) }
            try await inner(model, component, destination, progress)
        }
        let folder = store.location(of: .base)
        try writeWeights(
            into: folder.appending(path: "models/argmaxinc/whisperkit-coreml/\(SpeechModel.base.variant)"),
            files: Array(weightFiles.prefix(2)))

        try await store.install(.base) { _ in }

        #expect(fetched.withLock { $0 } == [.weights, .tokenizer])
        #expect(store.isInstalled(.base))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "models").path))
    }

    /// The weights arrive somewhere else first, so a process killed mid-download leaves the model's directory untouched.
    @Test("downloads the weights outside the model's directory and moves them in when complete")
    func stagesTheWeights() async throws {
        let sandbox = Sandbox()
        let seen = Mutex<URL?>(nil)
        let inner = writingDownloader()
        let store = FileSystemSpeechModelStore(root: sandbox.root) {
            model, component, destination, progress in
            if component == .weights { seen.withLock { $0 = destination } }
            try await inner(model, component, destination, progress)
        }

        try await store.install(.base) { _ in }

        let staged = try #require(seen.withLock { $0 })
        #expect(staged.standardizedFileURL != store.location(of: .base).standardizedFileURL)
        #expect(!FileManager.default.fileExists(atPath: staged.path), "the staging directory is consumed")
        #expect(store.isInstalled(.base))
    }

    /// A tokenizer fetched before the weights stays put when the complete weights are moved in.
    @Test("keeps a tokenizer already on disk when the weights arrive")
    func keepsTheTokenizerWhenTheWeightsArrive() async throws {
        let sandbox = Sandbox()
        let fetched = Mutex<[ModelComponent]>([])
        let inner = writingDownloader()
        let store = FileSystemSpeechModelStore(root: sandbox.root) {
            model, component, destination, progress in
            fetched.withLock { $0.append(component) }
            try await inner(model, component, destination, progress)
        }
        let folder = store.location(of: .base)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writeTokenizer(into: folder)

        try await store.install(.base) { _ in }

        #expect(fetched.withLock { $0 } == [.weights])
        #expect(store.isInstalled(.base))
    }

    /// A failed swap after the tokenizer is staged must leave the destination's own tokenizer alone.
    @Test("keeps the destination's tokenizer when the swap that follows staging it fails")
    func tokenizerSurvivesAFailedSwap() async throws {
        let sandbox = Sandbox()
        let hasLockedRootOnce = Mutex(false)
        let store = FileSystemSpeechModelStore(root: sandbox.root) { _, component, destination, _ in
            switch component {
            case .weights:
                try writeWeights(into: destination)
                // Locked only on the first attempt, so a retry after this test unlocks it can finish.
                let wasLocked = hasLockedRootOnce.withLock { locked -> Bool in
                    defer { locked = true }
                    return locked
                }
                if !wasLocked {
                    try FileManager.default.setAttributes(
                        [.posixPermissions: 0o555], ofItemAtPath: sandbox.root.path)
                }
            case .tokenizer:
                try writeTokenizer(into: destination)
            }
        }
        let folder = store.location(of: .base)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writeTokenizer(into: folder)
        let original = try Data(contentsOf: folder.appending(path: TokenizerAssets.fileNames[0]))

        // Root read-only after the weights land, so the swap needs a rename root now refuses.
        await #expect(throws: SpeechEngineError.self) { try await store.install(.base) { _ in } }

        #expect(!store.isInstalled(.base), "the swap did not happen")
        for name in TokenizerAssets.fileNames {
            #expect(
                FileManager.default.fileExists(atPath: folder.appending(path: name).path),
                "the destination's own \(name) must survive a swap that never happened")
        }
        #expect(try Data(contentsOf: folder.appending(path: TokenizerAssets.fileNames[0])) == original)

        // Recovery: once the directory can be swapped, the very same install finishes normally.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: sandbox.root.path)
        try await store.install(.base) { _ in }
        #expect(store.isInstalled(.base))
    }

    /// Files a failed download already fetched stay in staging, so asking again resumes rather than restarts.
    @Test("keeps a failed weights download in staging and leaves the model's directory alone")
    func failedWeightsDownloadStaysStaged() async throws {
        struct Boom: Error {}
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root) { _, _, destination, _ in
            try writeWeights(into: destination, files: Array(weightFiles.prefix(2)))
            throw Boom()
        }

        await #expect(throws: SpeechEngineError.self) { try await store.install(.base) { _ in } }

        let staged = store.stagingLocation(of: .base).appending(path: weightFiles[0])
        #expect(FileManager.default.fileExists(atPath: staged.path))
        #expect(!FileManager.default.fileExists(atPath: store.location(of: .base).path))
        #expect(!store.isInstalled(.base))
    }

    /// A download that says it finished but left bundles out is thrown away rather than moved in.
    @Test("discards staged weights that are incomplete when the download reports success")
    func incompleteStagedWeightsDiscarded() async {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root) { _, _, destination, _ in
            try writeWeights(into: destination, files: Array(weightFiles.dropLast()))
        }

        await #expect(throws: SpeechEngineError.self) { try await store.install(.base) { _ in } }

        #expect(!FileManager.default.fileExists(atPath: store.stagingLocation(of: .base).path))
        #expect(!FileManager.default.fileExists(atPath: sandbox.root.appending(path: ".partial").path))
        #expect(!store.isInstalled(.base))
    }

    // MARK: Disk space

    /// The free space an install of `.base` asks for when nothing is staged yet.
    private var baseNeeds: Int64 { SpeechModel.base.downloadBytes + FileSystemSpeechModelStore.installMargin }

    @Test("refuses to start a download the disk cannot hold, and says how much space it needs")
    func refusesWhenTheDiskIsTooFull() async {
        let sandbox = Sandbox()
        let fetched = Mutex(0)
        let inner = writingDownloader()
        let store = FileSystemSpeechModelStore(
            root: sandbox.root,
            download: { model, component, destination, progress in
                fetched.withLock { $0 += 1 }
                try await inner(model, component, destination, progress)
            },
            availableCapacity: { [baseNeeds] _ in baseNeeds - 1 })

        await #expect(throws: SpeechEngineError.notEnoughSpace(neededBytes: baseNeeds)) {
            try await store.install(.base) { _ in }
        }
        #expect(fetched.withLock { $0 } == 0, "nothing is downloaded onto a full disk")
    }

    @Test("starts the download when the disk holds exactly what it needs, or cannot say")
    func startsWhenItFits() async throws {
        for capacity in [baseNeeds, nil] {
            let sandbox = Sandbox()
            let store = FileSystemSpeechModelStore(
                root: sandbox.root, download: writingDownloader(), availableCapacity: { _ in capacity })

            try await store.install(.base) { _ in }

            #expect(store.isInstalled(.base))
        }
    }

    @Test("counts what an earlier attempt already staged against the space it asks for")
    func creditsStagedBytes() async throws {
        let sandbox = Sandbox()
        let staged = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())
        try writeWeights(into: staged.stagingLocation(of: .base), files: [weightFiles[1]], bytesEach: 1_000)
        let store = FileSystemSpeechModelStore(
            root: sandbox.root, download: writingDownloader(),
            availableCapacity: { [baseNeeds] _ in baseNeeds - 1_000 })

        try await store.install(.base) { _ in }

        #expect(store.isInstalled(.base))
    }

    @Test(
        "reports a disk that fills up mid-download as a full disk, not a connection",
        arguments: [
            NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError),
            NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)),
            NSError(
                domain: NSURLErrorDomain, code: NSURLErrorCannotWriteToFile,
                userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))]),
        ])
    func outOfSpaceMidDownload(error: NSError) async {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(
            root: sandbox.root, download: { _, _, _, _ in throw error }, availableCapacity: { _ in nil })

        await #expect(throws: SpeechEngineError.notEnoughSpace(neededBytes: baseNeeds)) {
            try await store.install(.base) { _ in }
        }
    }

    @Test("reports a full disk while fetching the tokenizer the same way")
    func outOfSpaceFetchingTheTokenizer() async {
        let sandbox = Sandbox()
        let inner = writingDownloader()
        let store = FileSystemSpeechModelStore(
            root: sandbox.root,
            download: { model, component, destination, progress in
                guard component == .tokenizer else {
                    return try await inner(model, component, destination, progress)
                }
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
            },
            availableCapacity: { _ in nil })

        await #expect(
            throws: SpeechEngineError.notEnoughSpace(neededBytes: FileSystemSpeechModelStore.installMargin)
        ) {
            try await store.install(.base) { _ in }
        }
    }

    @Test("keeps the connection message for a network failure")
    func networkFailureKeepsItsWording() async throws {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(
            root: sandbox.root, download: { _, _, _, _ in throw URLError(.notConnectedToInternet) },
            availableCapacity: { _ in nil })

        let failure = await #expect(throws: SpeechEngineError.self) {
            try await store.install(.base) { _ in }
        }

        let reported = try #require(failure)
        guard case .modelDownloadFailed = reported else {
            Issue.record("expected a download failure, got \(reported)")
            return
        }
        #expect(reported.userMessage.contains("connection"))
    }

    @Test("reads the free space of the volume a folder not yet made would sit on")
    func readsTheRealVolume() {
        let sandbox = Sandbox()
        let missing = sandbox.root.appending(path: "Models/not-yet", directoryHint: .isDirectory)

        #expect((FileSystemSpeechModelStore.availableCapacity(at: missing) ?? 0) > 0)
    }

    @Test("removing a model also discards its half-finished download")
    func removeDiscardsStaging() throws {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())
        try writeWeights(into: store.stagingLocation(of: .base), files: [weightFiles[0]])

        try store.remove(.base)

        #expect(!FileManager.default.fileExists(atPath: store.stagingLocation(of: .base).path))
    }

    @Test("names every file of every bundle a load reads, not only the weights")
    func namesTheWeightFiles() {
        for bundle in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            #expect(weightFiles.contains("\(bundle).mlmodelc/model.mil"))
            #expect(weightFiles.contains("\(bundle).mlmodelc/coremldata.bin"))
            #expect(weightFiles.contains("\(bundle).mlmodelc/weights/weight.bin"))
        }
        #expect(weightFiles.contains("config.json"))
        #expect(weightFiles.contains("generation_config.json"))
    }

    /// The live failure: bundles with weights and no `model.mil`, a missing prefill bundle, no config.
    @Test("calls a folder holding only each bundle's weights incomplete, not installed")
    func weightsOnlyFolderIsIncomplete() throws {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())
        let folder = store.location(of: .largeV3Turbo)
        let weightsOnly = ["MelSpectrogram", "AudioEncoder", "TextDecoder"].flatMap {
            ["\($0).mlmodelc/coremldata.bin", "\($0).mlmodelc/weights/weight.bin"]
        }
        try writeWeights(into: folder, files: weightsOnly)
        try writeTokenizer(into: folder)

        #expect(!store.isInstalled(.largeV3Turbo))
        #expect(store.isIncomplete(.largeV3Turbo))
        #expect(WeightsAssets.missing(for: .largeV3Turbo, in: folder).contains("config.json"))
    }

    @Test("does not call a model that was never downloaded incomplete")
    func absentFolderIsNotIncomplete() {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())

        #expect(!store.isIncomplete(.base))
    }

    @Test("does not call an installed model incomplete")
    func installedModelIsNotIncomplete() async throws {
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root, download: writingDownloader())
        try await store.install(.base) { _ in }

        #expect(!store.isIncomplete(.base))
    }

    /// An interrupted download must never leave a folder that reads as installed.
    @Test("an interrupted download never counts as installed", arguments: [1, 5, 12])
    func interruptedDownloadIsNeverInstalled(filesBeforeDrop: Int) async {
        struct Dropped: Error {}
        let sandbox = Sandbox()
        let store = FileSystemSpeechModelStore(root: sandbox.root) { _, component, destination, _ in
            guard component == .weights else { return try writeTokenizer(into: destination) }
            try writeWeights(into: destination, files: Array(weightFiles.prefix(filesBeforeDrop)))
            throw Dropped()
        }

        await #expect(throws: SpeechEngineError.self) { try await store.install(.base) { _ in } }

        #expect(!store.isInstalled(.base))
        #expect(!FileManager.default.fileExists(atPath: store.location(of: .base).path))
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
    @Test("creates no model directory when the download fails")
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
