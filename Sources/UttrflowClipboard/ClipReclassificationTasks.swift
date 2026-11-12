// The background detector passes over stale indexes, one at a time per index.

import Foundation

/// Holds each index's running detector pass, so a read can return while classification runs.
struct ClipReclassificationTasks {
    /// What a finished pass hands back to the store: the reclassified candidates.
    typealias Finish = @Sendable ([Clip]) async -> Void

    private var running: [URL: Task<Void, Never>] = [:]

    /// Whether a pass over this index has started and not yet finished.
    func isRunning(_ url: URL) -> Bool {
        running[url] != nil
    }

    /// Classifies the text clips of one index at utility priority, then hands the result to `finish`.
    mutating func start(_ url: URL, classifying clips: [Clip], then finish: @escaping Finish) {
        let candidates = clips.filter { $0.image == nil && $0.files == nil }
        running[url] = Task {
            let updated = await Task.detached(priority: .utility) {
                await ClipReclassification.classify(candidates)
            }.value
            await finish(updated)
        }
    }

    /// Forgets a pass once its result has been written or refused.
    mutating func finished(_ url: URL) {
        running[url] = nil
    }

    /// Every pass still running, for a test that waits on them.
    var pending: [Task<Void, Never>] {
        Array(running.values)
    }
}
