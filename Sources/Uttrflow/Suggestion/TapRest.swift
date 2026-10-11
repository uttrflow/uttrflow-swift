import Foundation

/// The one pending restart of a rested tap, which a stop cancels so the tap never comes back on its own.
@MainActor
final class TapRest {
    private var pending: Task<Void, Never>?

    /// Whether a restart is still waiting.
    var isPending: Bool { pending != nil }

    /// Replaces any waiting restart with one that runs after `delay`, unless cancelled first.
    func schedule(
        after delay: Duration,
        shouldRestart: @escaping @MainActor () -> Bool = { true },
        willRestart: @escaping @MainActor () -> Void = {},
        restart: @escaping @MainActor () -> Void
    ) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.pending = nil
            guard shouldRestart() else { return }
            willRestart()
            restart()
        }
    }

    /// Drops the waiting restart, if any.
    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
