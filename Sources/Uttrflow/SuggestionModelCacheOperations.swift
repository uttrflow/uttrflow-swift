import Foundation

@MainActor
final class SuggestionModelCacheOperations {
    private let release: (@Sendable () async -> Void)?
    private let readBytes: @Sendable () -> Int64?
    private let removeFiles: (@Sendable () throws -> Void)?
    private var stopModel: (@MainActor () -> Task<Void, Never>?)?
    private var onCacheChange: (@MainActor () -> Void)?
    private var probeGeneration = 0
    private(set) var cachedBytesOnDisk: Int64?
    private(set) var isRemovingCache = false

    init(
        release: (@Sendable () async -> Void)?,
        readBytes: @escaping @Sendable () -> Int64?,
        removeFiles: (@Sendable () throws -> Void)?
    ) {
        self.release = release
        self.readBytes = readBytes
        self.removeFiles = removeFiles
    }

    func configure(
        stopModel: @escaping @MainActor () -> Task<Void, Never>?,
        onCacheChange: @escaping @MainActor () -> Void
    ) {
        self.stopModel = stopModel
        self.onCacheChange = onCacheChange
    }

    func probeCache() {
        probeGeneration += 1
        let generation = probeGeneration
        let readBytes = readBytes
        Task { [weak self] in
            let bytes = await Task.detached(priority: .utility) { readBytes() }.value
            guard let self, generation == probeGeneration, !isRemovingCache else { return }
            cachedBytesOnDisk = bytes
            onCacheChange?()
        }
    }

    func releaseModel() async {
        await release?()
    }

    func removeCachedFiles() async throws {
        isRemovingCache = true
        probeGeneration += 1
        defer {
            isRemovingCache = false
            onCacheChange?()
        }
        let previous = stopModel?()
        if let previous {
            await previous.value
        } else {
            await releaseModel()
        }
        let removeFiles = removeFiles
        try await Task.detached(priority: .utility) { try removeFiles?() }.value
        cachedBytesOnDisk = 0
    }

    func removeCachedFiles(onFailure: @escaping @MainActor (any Error) -> Void) -> Task<Void, Never> {
        Task {
            do {
                try await removeCachedFiles()
            } catch {
                onFailure(error)
            }
        }
    }
}
