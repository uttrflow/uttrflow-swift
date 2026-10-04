import Foundation

/// Shares one model load, letting a download caller retry after a disk-only miss.
actor InFlightModelLoad {
    private struct Entry {
        let id: UUID
        let downloads: Bool
        let task: Task<Void, any Error>
    }

    private var entry: Entry?
    private(set) var joinerCount = 0

    /// Cancels the active load when its model is released.
    func cancel() {
        entry?.task.cancel()
        entry = nil
    }

    /// Joins a load, or retries a disk-only miss with the caller's download operation.
    func run(
        downloads: Bool,
        shouldRetry: @Sendable (any Error) -> Bool,
        operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        if let current = entry {
            joinerCount += 1
            defer { joinerCount -= 1 }
            do {
                try await current.task.value
            } catch {
                guard downloads, !current.downloads, shouldRetry(error) else { throw error }
                guard entry?.id == current.id else {
                    return try await run(downloads: downloads, shouldRetry: shouldRetry, operation: operation)
                }
                let retry = start(downloads: true, operation: operation)
                entry = retry
                defer { if entry?.id == retry.id { entry = nil } }
                try await withTaskCancellationHandler(
                    operation: { try await retry.task.value },
                    onCancel: { retry.task.cancel() })
            }
            return
        }

        let started = start(downloads: downloads, operation: operation)
        entry = started
        defer { if entry?.id == started.id { entry = nil } }
        try await withTaskCancellationHandler(
            operation: { try await started.task.value },
            onCancel: { started.task.cancel() })
    }

    private func start(
        downloads: Bool, operation: @escaping @Sendable () async throws -> Void
    ) -> Entry {
        Entry(id: UUID(), downloads: downloads, task: Task { try await operation() })
    }
}
