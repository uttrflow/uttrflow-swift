public import Foundation
public import UttrflowCore

/// One separately fetchable part of an installed model.
///
/// The two come from different repositories and go missing independently — an install
/// made before the tokenizer was part of one has weights and nothing else — so the
/// store asks for them one at a time instead of treating an install as all or nothing.
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
    func isInstalled(_ model: SpeechModel) -> Bool
    /// Models present on disk, in catalogue order.
    func installedModels() -> [SpeechModel]
    /// Bytes this model occupies, or `nil` when it is not installed.
    func bytesOnDisk(_ model: SpeechModel) -> Int64?

    /// Installs the model, reporting progress from `0` to `1`.
    ///
    /// - Returns: Where the files ended up. Returns immediately if already installed.
    /// - Throws: ``SpeechEngineError/modelDownloadFailed(description:)``.
    @discardableResult
    func install(
        _ model: SpeechModel, onProgress: @escaping @Sendable (Double) -> Void
    ) async throws(SpeechEngineError) -> URL

    /// Deletes the model. Does nothing if it is not installed.
    func remove(_ model: SpeechModel) throws(SpeechEngineError)
}

/// A store backed by a directory.
///
/// The download itself is injected, so everything else — where files go, what counts
/// as installed, refusing to re-download, cleaning up a failed install — is testable
/// against a temporary directory with no network.
public struct FileSystemSpeechModelStore: SpeechModelStore {
    /// Fetches one part of one model into the given directory.
    public typealias Downloader =
        @Sendable (SpeechModel, ModelComponent, URL, @escaping @Sendable (Double) -> Void)
        async throws -> Void

    public let root: URL
    private let download: Downloader

    public init(root: URL, download: @escaping Downloader) {
        self.root = root
        self.download = download
    }

    /// `FileManager` is not `Sendable`, and the shared instance is documented as safe
    /// for the file operations used here. Tests run against real temporary
    /// directories, which is more faithful than a substitute would be.
    private var fileManager: FileManager { .default }

    /// Where models live when the app has not been told otherwise.
    public static func defaultRoot() -> URL {
        let base =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appending(path: "Uttrflow/Models", directoryHint: .isDirectory)
    }

    public func location(of model: SpeechModel) -> URL {
        root.appending(path: model.variant, directoryHint: .isDirectory)
    }

    /// A model counts as installed only when everything needed to transcribe with it is
    /// on disk: the weights *and* the tokenizer.
    ///
    /// The weights alone used to be enough, and that made this method a lie. WhisperKit
    /// will quietly fetch a missing tokenizer from Hugging Face the first time somebody
    /// dictates — on a plane, an unrecoverable failure reported as a load error rather
    /// than the missing download it actually is. Answering `false` is what puts the
    /// offer to install back in front of the user, which is the whole remedy for an
    /// install made by an earlier build.
    ///
    /// An empty directory is what a cancelled download leaves behind, and is likewise
    /// not installed: treating it as installed would fail later, further from the cause.
    public func isInstalled(_ model: SpeechModel) -> Bool {
        missingComponents(of: model).isEmpty
    }

    /// The parts of `model` still to be fetched, weights first.
    ///
    /// Ordered because the weights are the wait: they own the progress bar, and asking
    /// for them first means the bar starts moving straight away.
    func missingComponents(of model: SpeechModel) -> [ModelComponent] {
        let folder = location(of: model)
        return ModelComponent.allCases.filter { component in
            switch component {
            // Any file that is not part of the tokenizer, since a directory holding
            // nothing but a tokenizer has no model in it.
            case .weights:
                !files(in: folder).contains {
                    !TokenizerAssets.fileNames.contains($0.lastPathComponent)
                }
            case .tokenizer:
                !TokenizerAssets.arePresent(in: folder)
            }
        }
    }

    public func installedModels() -> [SpeechModel] {
        SpeechModel.catalogue.filter(isInstalled)
    }

    public func bytesOnDisk(_ model: SpeechModel) -> Int64? {
        guard isInstalled(model) else { return nil }
        return files(in: location(of: model)).reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    /// Installs whatever parts of the model are not already there.
    ///
    /// Fetching only what is missing is what keeps an install made by an earlier build
    /// cheap to repair: those have the weights and no tokenizer, and re-downloading six
    /// hundred megabytes to add three would be a poor way to apologise.
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

        // A download that reported success and produced nothing is the case that used
        // to be discovered a launch later, as a model that would not load.
        guard !missingComponents(of: model).contains(component) else {
            unwind(component, at: destination)
            throw .modelDownloadFailed(
                description: "the download completed but \(component.described) did not arrive")
        }
    }

    /// Undoes a fetch that got part way, in proportion to what it was fetching.
    ///
    /// A failed weights download takes the whole directory: what it left is unusable and
    /// indistinguishable from a complete install by size alone. A failed tokenizer fetch
    /// takes only the tokenizer, because the weights beside it may be six hundred
    /// megabytes the user has already waited for and are still perfectly good — and
    /// ``isInstalled`` already refuses to call what remains usable, so nothing can
    /// mistake it for a working model in the meantime.
    private func unwind(_ component: ModelComponent, at destination: URL) {
        switch component {
        case .weights: try? fileManager.removeItem(at: destination)
        case .tokenizer: TokenizerAssets.remove(from: destination)
        }
    }

    public func remove(_ model: SpeechModel) throws(SpeechEngineError) {
        let location = location(of: model)
        guard fileManager.fileExists(atPath: location.path) else { return }
        do {
            try fileManager.removeItem(at: location)
        } catch {
            throw .modelLoadFailed(description: error.localizedDescription)
        }
    }

    /// Moves everything in `source` up into `destination`, then removes what the
    /// download left wrapped around it.
    ///
    /// Model repositories nest their output — WhisperKit's lands in
    /// `destination/models/<repo>/<variant>/`. The store's contract is that a model's
    /// files sit directly in ``location(of:)``, so the nesting is undone here rather
    /// than leaking into every caller that needs a path.
    public static func hoist(contentsOf source: URL, into destination: URL) throws {
        let fileManager = FileManager.default
        guard source.standardizedFileURL != destination.standardizedFileURL else { return }

        // Remember the wrapper directly under the destination before moving anything;
        // afterwards there is nothing left to identify it by.
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
