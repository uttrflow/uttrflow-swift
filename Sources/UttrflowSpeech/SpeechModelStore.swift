public import Foundation
public import UttrflowCore

// Where speech models live on disk, and how they get there one component at a time.
/// One separately fetchable part of a model, since the two go missing independently.
public enum ModelComponent: Sendable, Hashable, CaseIterable {
    /// The CoreML weights the recogniser runs.
    case weights
    /// The vocabulary it turns those weights' output back into words with.
    case tokenizer

    /// How this part is named in a diagnostic.
    var described: String {
        switch self {
        case .weights: "the model weights"
        case .tokenizer: "the tokenizer"
        }
    }
}

/// Where speech models live on disk, and how they get there.
public protocol SpeechModelStore: Sendable {
    /// Where this model's files belong, installed or not.
    func location(of model: SpeechModel) -> URL
    /// Whether everything needed to transcribe with this model is on disk.
    func isInstalled(_ model: SpeechModel) -> Bool
    /// Models present on disk, in catalogue order.
    func installedModels() -> [SpeechModel]
    /// Bytes this model occupies, or `nil` when it is not installed.
    func bytesOnDisk(_ model: SpeechModel) -> Int64?

    /// Installs the model, reporting progress from `0` to `1`, and answers with where the files are.
    @discardableResult
    func install(
        _ model: SpeechModel, onProgress: @escaping @Sendable (Double) -> Void
    ) async throws(SpeechEngineError) -> URL

    /// Deletes the model. Does nothing if it is not installed.
    func remove(_ model: SpeechModel) throws(SpeechEngineError)
}

/// What a model's compiled weights consist of; WhisperKit cannot load a directory missing any of them.
public enum WeightsAssets {
    /// The compiled bundles every WhisperKit variant needs to turn audio into tokens.
    public static let bundleNames = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]

    /// The files a load reads from each bundle, relative to the model's directory.
    public static let fileNames: [String] = bundleNames.flatMap {
        ["\($0).mlmodelc/coremldata.bin", "\($0).mlmodelc/weights/weight.bin"]
    }

    /// Whether every weight file sits in `folder` and holds at least one byte.
    public static func arePresent(in folder: URL) -> Bool {
        fileNames.allSatisfy { name in
            let size = try? folder.appending(path: name).resourceValues(forKeys: [.fileSizeKey]).fileSize
            return (size ?? 0) > 0
        }
    }
}

/// A store backed by a directory, with the download injected. See `Docs/speech-model-install.md`.
public struct FileSystemSpeechModelStore: SpeechModelStore {
    /// Fetches one part of one model into the given directory.
    public typealias Downloader =
        @Sendable (SpeechModel, ModelComponent, URL, @escaping @Sendable (Double) -> Void)
        async throws -> Void

    /// Answers how many bytes the volume holding a URL can still take, or `nil` when it cannot say.
    public typealias CapacityReader = @Sendable (URL) -> Int64?

    /// Free space asked for beyond the download itself, so the disk is not left completely full.
    static let installMargin: Int64 = 200_000_000

    /// The directory every model's folder sits in.
    public let root: URL
    /// How one component of one model is fetched.
    private let download: Downloader
    /// How much the disk can take, checked before a download starts.
    private let availableCapacity: CapacityReader

    /// Puts models under `root` and fetches them with `download`, once `availableCapacity` says they fit.
    public init(
        root: URL, download: @escaping Downloader,
        availableCapacity: @escaping CapacityReader = FileSystemSpeechModelStore.availableCapacity(at:)
    ) {
        self.root = root
        self.download = download
        self.availableCapacity = availableCapacity
    }

    /// The space the system will free for an important write on the volume holding `url`, read from its nearest existing folder.
    public static func availableCapacity(at url: URL) -> Int64? {
        var folder = url
        while !FileManager.default.fileExists(atPath: folder.path), folder.pathComponents.count > 1 {
            folder = folder.deletingLastPathComponent()
        }
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Named rather than held, because `FileManager` is not `Sendable` though the shared one is safe here.
    private var fileManager: FileManager { .default }

    /// Where models live when the app has not been told otherwise.
    public static func defaultRoot() -> URL {
        let base =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return LocalStore.directory("Models", in: base)
    }

    public func location(of model: SpeechModel) -> URL {
        root.appending(path: model.variant, directoryHint: .isDirectory)
    }

    /// Where this model's weights download before they are complete, so a killed download never reads as installed.
    func stagingLocation(of model: SpeechModel) -> URL {
        stagingRoot.appending(path: model.variant, directoryHint: .isDirectory)
    }

    /// The directory every half-finished weights download sits in, hidden beside the models.
    private var stagingRoot: URL {
        root.appending(path: ".partial", directoryHint: .isDirectory)
    }

    /// Whether the weights *and* the tokenizer are on disk. See `Docs/speech-model-install.md`.
    public func isInstalled(_ model: SpeechModel) -> Bool {
        missingComponents(of: model).isEmpty
    }

    /// The parts of `model` still to be fetched, weights first because they own the progress bar.
    func missingComponents(of model: SpeechModel) -> [ModelComponent] {
        let folder = location(of: model)
        return ModelComponent.allCases.filter { component in
            switch component {
            case .weights:
                !WeightsAssets.arePresent(in: folder)
            case .tokenizer:
                !TokenizerAssets.arePresent(in: folder)
            }
        }
    }

    /// Models present on disk, in catalogue order.
    public func installedModels() -> [SpeechModel] {
        SpeechModel.catalogue.filter(isInstalled)
    }

    /// Bytes this model occupies, or `nil` when it is not installed.
    public func bytesOnDisk(_ model: SpeechModel) -> Int64? {
        guard isInstalled(model) else { return nil }
        return files(in: location(of: model)).reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    /// Installs whatever parts of the model are not already there, so a repair fetches only those.
    @discardableResult
    public func install(
        _ model: SpeechModel, onProgress: @escaping @Sendable (Double) -> Void
    ) async throws(SpeechEngineError) -> URL {
        let destination = location(of: model)
        for component in missingComponents(of: model) {
            switch component {
            case .weights:
                try await fetchWeights(of: model, into: destination, onProgress: onProgress)
            case .tokenizer:
                try await fetchTokenizer(of: model, into: destination, onProgress: onProgress)
            }
        }

        onProgress(1)
        return destination
    }

    /// Downloads the weights into staging and moves them into place only once all of them are there.
    private func fetchWeights(
        of model: SpeechModel, into destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws(SpeechEngineError) {
        let staging = stagingLocation(of: model)
        let needed = spaceNeeded(for: model, stagedIn: staging)
        if let available = availableCapacity(root), available < needed {
            throw .notEnoughSpace(neededBytes: needed)
        }
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            // Staging is kept on failure, so asking again resumes from the files already fetched.
            try await download(model, .weights, staging, onProgress)
        } catch {
            throw Self.failure(error, needing: needed)
        }

        // Checked here, or a download that reports success and produces nothing surfaces a launch later.
        guard WeightsAssets.arePresent(in: staging) else {
            discardStaging(of: model)
            throw .modelDownloadFailed(
                description: "the download completed but \(ModelComponent.weights.described) did not arrive")
        }

        do {
            try commit(staging, into: destination)
        } catch {
            throw Self.failure(error, needing: needed)
        }
    }

    /// The rest of the download plus the margin, counting what an earlier attempt already staged.
    private func spaceNeeded(for model: SpeechModel, stagedIn staging: URL) -> Int64 {
        let staged = files(in: staging).reduce(Int64(0)) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return max(model.downloadBytes - staged, 0) + Self.installMargin
    }

    /// Says the disk is full when it is, and that the download failed otherwise.
    static func failure(_ error: any Error, needing neededBytes: Int64) -> SpeechEngineError {
        isOutOfSpace(error)
            ? .notEnoughSpace(neededBytes: neededBytes)
            : .modelDownloadFailed(description: error.localizedDescription)
    }

    /// Whether `error`, or any error beneath it, is the disk running out of room.
    static func isOutOfSpace(_ error: any Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteOutOfSpaceError { return true }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOSPC) { return true }
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? any Error else { return false }
        return isOutOfSpace(underlying)
    }

    /// Swaps complete staged weights in for the model's directory, carrying over a tokenizer already there.
    private func commit(_ staging: URL, into destination: URL) throws {
        for name in TokenizerAssets.fileNames {
            let existing = destination.appending(path: name)
            let staged = staging.appending(path: name)
            if fileManager.fileExists(atPath: existing.path), !fileManager.fileExists(atPath: staged.path) {
                try fileManager.moveItem(at: existing, to: staged)
            }
        }
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
        removeStagingRootIfEmpty()
    }

    /// Fetches the tokenizer beside the weights, and removes half of one rather than leave it.
    private func fetchTokenizer(
        of model: SpeechModel, into destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws(SpeechEngineError) {
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try await download(model, .tokenizer, destination, onProgress)
        } catch {
            TokenizerAssets.remove(from: destination)
            throw Self.failure(error, needing: Self.installMargin)
        }

        guard TokenizerAssets.arePresent(in: destination) else {
            TokenizerAssets.remove(from: destination)
            throw .modelDownloadFailed(
                description: "the download completed but \(ModelComponent.tokenizer.described) did not arrive"
            )
        }
    }

    /// Deletes a half-finished weights download for `model`.
    private func discardStaging(of model: SpeechModel) {
        try? fileManager.removeItem(at: stagingLocation(of: model))
        removeStagingRootIfEmpty()
    }

    /// Removes the staging directory once no download is using it.
    private func removeStagingRootIfEmpty() {
        guard (try? fileManager.contentsOfDirectory(atPath: stagingRoot.path))?.isEmpty == true else {
            return
        }
        try? fileManager.removeItem(at: stagingRoot)
    }

    /// Deletes the model. Does nothing if it is not installed.
    public func remove(_ model: SpeechModel) throws(SpeechEngineError) {
        discardStaging(of: model)
        let location = location(of: model)
        guard fileManager.fileExists(atPath: location.path) else { return }
        do {
            try fileManager.removeItem(at: location)
        } catch {
            throw .modelLoadFailed(description: error.localizedDescription)
        }
    }

    /// Moves everything in `source` up into `destination`, undoing the nesting a repository adds.
    public static func hoist(contentsOf source: URL, into destination: URL) throws {
        let fileManager = FileManager.default
        guard source.standardizedFileURL != destination.standardizedFileURL else { return }

        // Identified before anything moves; afterwards there is nothing left to identify it by.
        let wrapper = source.standardizedFileURL.pathComponents
            .dropFirst(destination.standardizedFileURL.pathComponents.count)
            .first
            .map { destination.appending(path: $0, directoryHint: .isDirectory) }

        for child in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            let moved = destination.appending(path: child.lastPathComponent)
            if fileManager.fileExists(atPath: moved.path) {
                try fileManager.removeItem(at: moved)
            }
            try fileManager.moveItem(at: child, to: moved)
        }

        if let wrapper, fileManager.fileExists(atPath: wrapper.path) {
            try fileManager.removeItem(at: wrapper)
        }
    }

    // MARK: Directory inspection

    /// Every regular file under `directory`.
    private func files(in directory: URL) -> [URL] {
        guard
            let enumerator = fileManager.enumerator(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
            )
        else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }
}
