import Foundation
import Synchronization

/// Shares one model load among its callers, lets a download caller retry after a disk-only miss, and stops the load only once every caller waiting on it has gone.
actor InFlightModelLoad {
    typealias Progress = @Sendable (Double) -> Void

    /// Every waiting caller's progress callback, so one load reports to all of them.
    private final class Listeners: Sendable {
        private let callbacks = Mutex<[UUID: Progress]>([:])

        func set(_ caller: UUID, _ callback: Progress?) { callbacks.withLock { $0[caller] = callback } }

        func report(_ value: Double) {
            for callback in callbacks.withLock({ Array($0.values) }) { callback(value) }
        }
    }

    private struct Entry {
        let id: UUID
        let downloads: Bool
        let task: Task<Void, any Error>
        let listeners: Listeners
        var callers: Set<UUID> = []
    }

    private var entry: Entry?
    private(set) var joinerCount = 0

    /// Cancels the active load when its model is released.
    func cancel() {
        entry?.task.cancel()
        entry = nil
    }

    /// Joins a load or starts one, and retries a disk-only miss with the caller's download operation.
    func run(
        downloads: Bool,
        onProgress: @escaping Progress = { _ in },
        shouldRetry: @Sendable (any Error) -> Bool,
        operation: @escaping @Sendable (@escaping Progress) async throws -> Void
    ) async throws {
        let joining = entry != nil
        let current = entry ?? start(downloads: downloads, operation: operation)
        if joining { joinerCount += 1 }
        defer { if joining { joinerCount -= 1 } }
        do {
            try await wait(for: current, onProgress: onProgress)
        } catch {
            guard downloads, !current.downloads, shouldRetry(error), !Task.isCancelled else { throw error }
            try await run(
                downloads: downloads, onProgress: onProgress, shouldRetry: shouldRetry, operation: operation)
        }
    }

    private func start(
        downloads: Bool, operation: @escaping @Sendable (@escaping Progress) async throws -> Void
    ) -> Entry {
        let listeners = Listeners()
        let started = Entry(
            id: UUID(), downloads: downloads,
            task: Task { try await operation { listeners.report($0) } }, listeners: listeners)
        entry = started
        return started
    }

    /// Waits for the shared load; a cancelled caller leaves it running for the others and throws once it ends.
    private func wait(for current: Entry, onProgress: @escaping Progress) async throws {
        let caller = UUID()
        current.listeners.set(caller, onProgress)
        if entry?.id == current.id { entry?.callers.insert(caller) }
        defer {
            current.listeners.set(caller, nil)
            if entry?.id == current.id { entry = nil }
        }
        try await withTaskCancellationHandler(
            operation: { try await current.task.value },
            onCancel: { Task { await self.abandon(current.id, by: caller) } })
        try Task.checkCancellation()
    }

    /// Stops the shared load only when the last caller waiting on it is cancelled.
    private func abandon(_ id: UUID, by caller: UUID) {
        guard entry?.id == id else { return }
        entry?.callers.remove(caller)
        guard entry?.callers.isEmpty == true else { return }
        entry?.task.cancel()
        entry = nil
    }
}
