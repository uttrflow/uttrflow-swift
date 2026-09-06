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

/// A store backed by a directory, with the download injected. See `Docs/speech-model-install.md`.
public struct FileSystemSpeechModelStore: SpeechModelStore {
    /// Fetches one part of one model into the given directory.
    public typealias Downloader =
        @Sendable (SpeechModel, ModelComponent, URL, @escaping @Sendable (Double) -> Void)
        async throws -> Void

    /// The directory every model's folder sits in.
    public let root: URL
    /// How one component of one model is fetched.
    private let download: Downloader

    /// Puts models under `root` and fetches them with `download`.
    public init(root: URL, download: @escaping Downloader) {
        self.root = root
        self.download = download
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

    /// Whether the weights *and* the tokenizer are on disk. See `Docs/speech-model-install.md`.
    public func isInstalled(_ model: SpeechModel) -> Bool {
        missingComponents(of: model).isEmpty
    }

    /// The parts of `model` still to be fetched, weights first because they own the progress bar.
    func missingComponents(of model: SpeechModel) -> [ModelComponent] {
        let folder = location(of: model)
        return ModelComponent.allCases.filter { component in
            switch component {
            // Any file that is not the tokenizer's, since a tokenizer alone is no model.
            case .weights:
                !files(in: folder).contains {
                    !TokenizerAssets.fileNames.contains($0.lastPathComponent)
                }
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
            try await fetch(component, of: model, into: destination, onProgress: onProgress)
        }

        onProgress(1)
        return destination
    }

    /// Fetches one part, and leaves nothing behind that would be mistaken for it.
    private func fetch(
        _ component: ModelComponent, of model: SpeechModel, into destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws(SpeechEngineError) {
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try await download(model, component, destination, onProgress)
        } catch {
            unwind(component, at: destination)
            throw .modelDownloadFailed(description: error.localizedDescription)
        }

        // Checked here, or a download that reports success and produces nothing surfaces a launch later.
        guard !missingComponents(of: model).contains(component) else {
            unwind(component, at: destination)
            throw .modelDownloadFailed(
                description: "the download completed but \(component.described) did not arrive")
        }
    }

    /// Undoes a part-way fetch in proportion to it. See `Docs/speech-model-install.md`.
    private func unwind(_ component: ModelComponent, at destination: URL) {
        switch component {
        case .weights: try? fileManager.removeItem(at: destination)
        case .tokenizer: TokenizerAssets.remove(from: destination)
        }
    }

    /// Deletes the model. Does nothing if it is not installed.
    public func remove(_ model: SpeechModel) throws(SpeechEngineError) {
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
