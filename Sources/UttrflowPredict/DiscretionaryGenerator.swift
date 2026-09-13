// A generator run as work nobody is waiting for yet: at utility priority, and not at all when the Mac asks for less.

private import Synchronization

/// Wraps a generator so its passes run at utility priority and none starts while `mayRun` says no. See `Docs/performance.md`.
public struct DiscretionaryGenerator: CandidateGenerating {
    private let inner: any CandidateGenerating
    private let mayRun: @Sendable () -> Bool

    /// Takes the generator to run and the question asked before each pass, such as Low Power Mode and thermal pressure.
    public init(_ inner: any CandidateGenerating, mayRun: @escaping @Sendable () -> Bool) {
        self.inner = inner
        self.mayRun = mayRun
    }

    /// Not ready while the Mac asks for less, so the caller starts no pass and keeps what the corpus offers.
    public var isReady: Bool {
        get async {
            guard mayRun() else { return false }
            return await inner.isReady
        }
    }

    public func completions(for typed: String, in situation: GenerationSituation) async throws -> [String] {
        guard mayRun() else { return [] }
        return try await Self.discretionary { [inner] in
            try await inner.completions(for: typed, in: situation)
        }
    }

    public func alternatives(
        for typed: String, in situation: GenerationSituation, excluding leader: String
    ) async throws -> [String] {
        guard mayRun() else { return [] }
        return try await Self.discretionary { [inner] in
            try await inner.alternatives(for: typed, in: situation, excluding: leader)
        }
    }

    /// Runs the work in a utility task, resumed through a continuation so awaiting it does not raise its priority.
    static func discretionary(
        _ work: @escaping @Sendable () async throws -> [String]
    ) async throws -> [String] {
        let running = Mutex<(task: Task<Void, Never>?, cancelled: Bool)>((nil, false))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = Task.detached(priority: .utility) {
                    do {
                        continuation.resume(returning: try await work())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                // A cancellation that arrived before the task existed is passed on now.
                running.withLock { state in
                    state.task = task
                    if state.cancelled { task.cancel() }
                }
            }
        } onCancel: {
            running.withLock { state in
                state.cancelled = true
                state.task?.cancel()
            }
        }
    }
}
